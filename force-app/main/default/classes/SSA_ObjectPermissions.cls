public with sharing class SSA_ObjectPermissions {

    public class ActionInput {
        @InvocableVariable(label='Object Name' description='The Salesforce object API name to analyze. Can be any standard object like Account, Contact, Opportunity, Case, Lead, Task, Event, Campaign, Order, Product2, Contract, User, or any custom object ending in __c. Use all to analyze every object in the org.')
        public String objectName;

        @InvocableVariable(label='Reference Type' description='Profile or Permission Set or all')
        public String referenceType;

        @InvocableVariable(label='CRUD Filter' description='full_access or modify_all or delete or all')
        public String crudFilter;
    }

    public class ActionOutput {
        @InvocableVariable(label='Report Result')
        public String reportResult;

        @InvocableVariable(label='Total Entries')
        public Integer totalEntries;

        @InvocableVariable(label='Full CRED Count')
        public Integer fullCrudCount;

        @InvocableVariable(label='Modify All Count')
        public Integer modifyAllCount;
    }

    @InvocableMethod(
        label='SSA Object Permissions'
        description='Analyzes CRED access on objects across all profiles and permission sets. Shows who can Create Read Edit Delete View All and Modify All records.'
        category='SSA Org Analyzer'
    )
    public static List<ActionOutput> run(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();

            try {
                String objFilter = input.objectName != null ? input.objectName.trim() : 'all';
                String refFilter = input.referenceType != null ? input.referenceType.trim() : 'all';
                String crudFilter = input.crudFilter != null ? input.crudFilter.trim().toLowerCase() : 'all';

                String query =
                    'SELECT Id, SobjectType, ' +
                    'PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete, ' +
                    'PermissionsViewAllRecords, PermissionsModifyAllRecords, ' +
                    'Parent.Name, Parent.Label, Parent.IsOwnedByProfile, Parent.ProfileId, Parent.Id ' +
                    'FROM ObjectPermissions';

                if (objFilter != 'all') {
                    query += ' WHERE SobjectType = \'' +
                        String.escapeSingleQuotes(objFilter) + '\'';
                }
                query += ' ORDER BY SobjectType';

                List<ObjectPermissions> allOP = Database.query(query);

                // Profile name lookup
                Map<Id, String> profileNames = new Map<Id, String>();
                for (Profile pr : [SELECT Id, Name FROM Profile]) {
                    profileNames.put(pr.Id, pr.Name);
                }

                // Permission Set name lookup
                Map<Id, String> permSetNames = new Map<Id, String>();
                for (PermissionSet ps : [SELECT Id, Name, Label, IsOwnedByProfile FROM PermissionSet]) {
                    if (!ps.IsOwnedByProfile) {
                        String displayName = ps.Label != null ? ps.Label : (ps.Name != null ? ps.Name : 'PS-' + ps.Id);
                        permSetNames.put(ps.Id, displayName);
                    }
                }

                // COUNTERS
                Integer totalEntries = 0;
                Integer fullCrudCount = 0;
                Integer modifyAllCount = 0;
                Integer deleteCount = 0;
                Integer viewAllCount = 0;
                Integer createCount = 0;
                Integer readOnlyCount = 0;
                Integer profileEntries = 0;
                Integer permSetEntries = 0;
                Integer skippedByRefFilter = 0;
                Integer skippedByCrudFilter = 0;
                Integer totalProcessed = 0;

                List<String> modifyAllHolders = new List<String>();
                List<String> fullCrudHolders = new List<String>();

                Map<String, Map<String, Integer>> objectStats = new Map<String, Map<String, Integer>>();
                List<String> detailLines = new List<String>();

                for (ObjectPermissions op : allOP) {
                    totalProcessed++;

                    String refName;
                    String refType;

                    if (op.Parent.IsOwnedByProfile) {
                        refType = 'Profile';
                        if (op.Parent.ProfileId != null && profileNames.containsKey(op.Parent.ProfileId)) {
                            refName = profileNames.get(op.Parent.ProfileId);
                        } else if (op.Parent.Name != null) {
                            refName = op.Parent.Name;
                        } else {
                            refName = 'Unknown Profile';
                        }
                    } else {
                        refType = 'Permission Set';
                        if (op.Parent.Id != null && permSetNames.containsKey(op.Parent.Id)) {
                            refName = permSetNames.get(op.Parent.Id);
                        } else if (op.Parent.Label != null) {
                            refName = op.Parent.Label;
                        } else if (op.Parent.Name != null) {
                            refName = op.Parent.Name;
                        } else {
                            refName = 'Unnamed Permission Set (' + op.Parent.Id + ')';
                        }
                    }

                    // Apply reference type filter
                    if (refFilter != 'all' && !refType.equalsIgnoreCase(refFilter)) {
                        skippedByRefFilter++;
                        continue;
                    }

                    Boolean isFullCrud = op.PermissionsCreate && op.PermissionsRead &&
                        op.PermissionsEdit && op.PermissionsDelete;
                    Boolean isModifyAll = op.PermissionsModifyAllRecords;
                    Boolean isViewAll = op.PermissionsViewAllRecords;
                    Boolean hasDelete = op.PermissionsDelete;
                    Boolean hasCreate = op.PermissionsCreate;
                    Boolean isReadOnly = op.PermissionsRead && !op.PermissionsCreate &&
                        !op.PermissionsEdit && !op.PermissionsDelete;

                    // Apply CRUD filter
                    if (crudFilter == 'full_access' && !isFullCrud) { skippedByCrudFilter++; continue; }
                    if (crudFilter == 'modify_all' && !isModifyAll) { skippedByCrudFilter++; continue; }
                    if (crudFilter == 'delete' && !hasDelete) { skippedByCrudFilter++; continue; }

                    // COUNT everything
                    totalEntries++;
                    if (isFullCrud) fullCrudCount++;
                    if (isModifyAll) modifyAllCount++;
                    if (hasDelete) deleteCount++;
                    if (isViewAll) viewAllCount++;
                    if (hasCreate) createCount++;
                    if (isReadOnly) readOnlyCount++;
                    if (op.Parent.IsOwnedByProfile) profileEntries++; else permSetEntries++;

                    // Per-object stats
                    if (!objectStats.containsKey(op.SobjectType)) {
                        objectStats.put(op.SobjectType, new Map<String, Integer>{
                            'total' => 0, 'fullCred' => 0, 'modifyAll' => 0,
                            'delete' => 0, 'readOnly' => 0
                        });
                    }
                    Map<String, Integer> stats = objectStats.get(op.SobjectType);
                    stats.put('total', stats.get('total') + 1);
                    if (isFullCrud) stats.put('fullCred', stats.get('fullCred') + 1);
                    if (isModifyAll) stats.put('modifyAll', stats.get('modifyAll') + 1);
                    if (hasDelete) stats.put('delete', stats.get('delete') + 1);
                    if (isReadOnly) stats.put('readOnly', stats.get('readOnly') + 1);

                    // Key holders lists
                    if (isModifyAll && modifyAllHolders.size() < 50) {
                        modifyAllHolders.add(op.SobjectType + ' -> ' + refName + ' (' + refType + ')');
                    }
                    if (isFullCrud && fullCrudHolders.size() < 50) {
                        fullCrudHolders.add(op.SobjectType + ' -> ' + refName + ' (' + refType + ')');
                    }

                    // Detail lines
                    if (detailLines.size() < 100) {
                        String accessLevel;
                        if (isModifyAll) accessLevel = 'FULL+MODIFY ALL';
                        else if (isFullCrud && isViewAll) accessLevel = 'FULL CRED+VIEW ALL';
                        else if (isFullCrud) accessLevel = 'FULL CRED';
                        else if (isReadOnly) accessLevel = 'READ ONLY';
                        else if (op.PermissionsRead && op.PermissionsEdit && !op.PermissionsDelete)
                            accessLevel = 'READ+EDIT';
                        else if (op.PermissionsRead && op.PermissionsCreate && !op.PermissionsDelete)
                            accessLevel = 'READ+CREATE';
                        else accessLevel = 'CUSTOM';

                        detailLines.add(
                            '  ' + op.SobjectType + ' | ' + accessLevel + ' | ' +
                            'C:' + (op.PermissionsCreate ? 'Y' : 'N') +
                            ' R:' + (op.PermissionsRead ? 'Y' : 'N') +
                            ' E:' + (op.PermissionsEdit ? 'Y' : 'N') +
                            ' D:' + (op.PermissionsDelete ? 'Y' : 'N') +
                            ' VA:' + (op.PermissionsViewAllRecords ? 'Y' : 'N') +
                            ' MA:' + (op.PermissionsModifyAllRecords ? 'Y' : 'N') +
                            ' | ' + refName + ' (' + refType + ')'
                        );
                    }
                }

                // BUILD REPORT
                String report = '';

                report += 'OBJECT PERMISSION ANALYSIS REPORT\n';
                report += '=================================\n\n';

                report += 'FILTERS APPLIED:\n';
                report += '  Object: ' + objFilter + '\n';
                report += '  Reference Type: ' + refFilter + '\n';
                report += '  CRED Filter: ' + crudFilter + '\n\n';

                report += '-------------------------------------------\n';
                report += 'OVERALL SUMMARY\n';
                report += '-------------------------------------------\n';
                report += '  Total ObjectPermissions queried: ' + allOP.size() + '\n';
                report += '  Total processed: ' + totalProcessed + '\n';
                report += '  Skipped by reference filter: ' + skippedByRefFilter + '\n';
                report += '  Skipped by CRED filter: ' + skippedByCrudFilter + '\n';
                report += '  Matching all filters: ' + totalEntries + '\n';
                report += '  From Profiles: ' + profileEntries + '\n';
                report += '  From Permission Sets: ' + permSetEntries + '\n';
                report += '  Objects covered: ' + objectStats.size() + '\n\n';

                report += '  ACCESS LEVEL BREAKDOWN:\n';
                report += '    Full CRED (Create+Read+Edit+Delete): ' + fullCrudCount + '\n';
                report += '    Modify All Records: ' + modifyAllCount + '\n';
                report += '    View All Records: ' + viewAllCount + '\n';
                report += '    Delete access: ' + deleteCount + '\n';
                report += '    Create access: ' + createCount + '\n';
                report += '    Read Only: ' + readOnlyCount + '\n\n';

                // Per-object summary
                report += '-------------------------------------------\n';
                report += 'PER OBJECT SUMMARY (' + objectStats.size() + ' objects)\n';
                report += '-------------------------------------------\n';

                for (String objName : objectStats.keySet()) {
                    Map<String, Integer> sts = objectStats.get(objName);
                    report += '  ' + objName +
                        ' | Total: ' + sts.get('total') +
                        ' | Full CRED: ' + sts.get('fullCred') +
                        ' | Modify All: ' + sts.get('modifyAll') +
                        ' | Delete: ' + sts.get('delete') +
                        ' | Read Only: ' + sts.get('readOnly') + '\n';
                }
                report += '\n';

                // Modify All holders
                if (!modifyAllHolders.isEmpty()) {
                    report += '-------------------------------------------\n';
                    report += 'HIGHEST ACCESS: MODIFY ALL (' + modifyAllCount + ' total)\n';
                    report += '-------------------------------------------\n';
                    report += 'These bypass sharing rules entirely:\n\n';
                    for (String holder : modifyAllHolders) {
                        report += '  ** ' + holder + '\n';
                    }
                    if (modifyAllCount > 50) {
                        report += '  ... and ' + (modifyAllCount - 50) + ' more\n';
                    }
                    report += '\n';
                }

                // Full CRED holders
                if (!fullCrudHolders.isEmpty()) {
                    report += '-------------------------------------------\n';
                    report += 'FULL CRED ACCESS (' + fullCrudCount + ' total)\n';
                    report += '-------------------------------------------\n';
                    for (String holder : fullCrudHolders) {
                        report += '  * ' + holder + '\n';
                    }
                    if (fullCrudCount > 50) {
                        report += '  ... and ' + (fullCrudCount - 50) + ' more\n';
                    }
                    report += '\n';
                }

                // Detail
                report += '-------------------------------------------\n';
                report += 'DETAIL (showing ' + detailLines.size() + ' of ' + totalEntries + ')\n';
                report += '-------------------------------------------\n';
                for (String line : detailLines) {
                    report += line + '\n';
                }
                if (totalEntries > 100) {
                    report += '\n  ... ' + (totalEntries - 100) + ' more entries.\n';
                    report += '  Filter by specific object for full detail.\n';
                }
                report += '\n';

                // Security observations
                report += '-------------------------------------------\n';
                report += 'SECURITY OBSERVATIONS\n';
                report += '-------------------------------------------\n\n';

                if (modifyAllCount > 3) {
                    report += '  WARNING: ' + modifyAllCount + ' entries have Modify All Records. This bypasses sharing rules.\n\n';
                }
                if (fullCrudCount > 10) {
                    report += '  NOTE: ' + fullCrudCount + ' entries have full CRED. Review if Delete is needed for all.\n\n';
                }
                if (deleteCount > 0 && objFilter != 'all') {
                    report += '  INFO: ' + deleteCount + ' can delete ' + objFilter + ' records. Check data retention policy.\n\n';
                }
                if (profileEntries > 0 && permSetEntries > 0) {
                    report += '  TIP: Permissions from Profiles (' + profileEntries +
                        ') and Permission Sets (' + permSetEntries + '). Use minimum access profiles + permission sets.\n\n';
                }
                if (readOnlyCount > 0) {
                    report += '  GOOD: ' + readOnlyCount + ' entries are Read Only. Follows least privilege.\n\n';
                }

                output.reportResult = report;
                output.totalEntries = totalEntries;
                output.fullCrudCount = fullCrudCount;
                output.modifyAllCount = modifyAllCount;

            } catch (Exception e) {
                output.reportResult = 'Error: ' + e.getMessage() +
                    '\nVerify object name is correct. Use API name like Account, Contact, Case.';
                output.totalEntries = 0;
                output.fullCrudCount = 0;
                output.modifyAllCount = 0;
            }

            outputs.add(output);
        }
        return outputs;
    }
}