public with sharing class SSA_UserObjectPermissions {

    public class ActionInput {
        @InvocableVariable(label='Object Name' description='Object to analyze like Account or Contact or all')
        public String objectName;

        @InvocableVariable(label='CRED Filter' description='full_access or modify_all or delete or all')
        public String credFilter;

        @InvocableVariable(label='Profile Filter' description='Filter by profile name or all')
        public String profileFilter;

        @InvocableVariable(label='Active Only' description='Show only active users')
        public Boolean activeOnly;
    }

    public class ActionOutput {
        @InvocableVariable(label='Report Result')
        public String reportResult;

        @InvocableVariable(label='Total Users')
        public Integer totalUsers;

        @InvocableVariable(label='CSV Data')
        public String csvData;
    }

    @InvocableMethod(
        label='SSA Users With Object Permissions'
        description='Shows which actual users have specific object permissions.'
        category='SSA Org Analyzer'
    )
    public static List<ActionOutput> run(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();

            try {
                String objFilter = (input.objectName != null) ? input.objectName.trim() : 'all';
                String credFilter = (input.credFilter != null) ? input.credFilter.trim().toLowerCase() : 'all';
                String profileFilter = (input.profileFilter != null) ? input.profileFilter.trim() : 'all';
                Boolean activeOnly = (input.activeOnly != null) ? input.activeOnly : true;

                // Step 1: Get ObjectPermissions
                String opQuery = 'SELECT Id, SobjectType, ' +
                    'PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete, ' +
                    'PermissionsViewAllRecords, PermissionsModifyAllRecords, ' +
                    'ParentId, Parent.Name, Parent.Label, Parent.IsOwnedByProfile, Parent.ProfileId ' +
                    'FROM ObjectPermissions';

                if (objFilter != 'all') {
                    opQuery += ' WHERE SobjectType = \'' + String.escapeSingleQuotes(objFilter) + '\'';
                }

                List<ObjectPermissions> allOP = Database.query(opQuery);

                // Step 2: Filter by CRED level
                Set<Id> matchingPSIds = new Set<Id>();
                Map<Id, List<String>> psToObjects = new Map<Id, List<String>>();

                for (ObjectPermissions op : allOP) {
                    Boolean isFullCrud = op.PermissionsCreate && op.PermissionsRead && op.PermissionsEdit && op.PermissionsDelete;
                    Boolean isModifyAll = op.PermissionsModifyAllRecords;
                    Boolean isDelete = op.PermissionsDelete;

                    if (credFilter == 'full_access' && !isFullCrud) { continue; }
                    if (credFilter == 'modify_all' && !isModifyAll) { continue; }
                    if (credFilter == 'delete' && !isDelete) { continue; }

                    matchingPSIds.add(op.ParentId);

                    if (!psToObjects.containsKey(op.ParentId)) {
                        psToObjects.put(op.ParentId, new List<String>());
                    }
                    psToObjects.get(op.ParentId).add(op.SobjectType);
                }

                if (matchingPSIds.isEmpty()) {
                    output.reportResult = 'TOTAL USERS FOUND: 0\n\nNo users found matching filters.';
                    output.totalUsers = 0;
                    output.csvData = '';
                    outputs.add(output);
                    continue;
                }

                // Step 3: Get PermissionSet details
                Map<Id, PermissionSet> psMap = new Map<Id, PermissionSet>([
                    SELECT Id, Name, Label, IsOwnedByProfile, ProfileId
                    FROM PermissionSet
                    WHERE Id IN :matchingPSIds
                ]);

                // Step 4: Profile names
                Map<Id, String> profileNames = new Map<Id, String>();
                for (Profile pr : [SELECT Id, Name FROM Profile]) {
                    profileNames.put(pr.Id, pr.Name);
                }

                // Step 5: Find users
                String psaQuery = 'SELECT Id, AssigneeId, PermissionSetId, ' +
                    'Assignee.Name, Assignee.Username, Assignee.Email, ' +
                    'Assignee.IsActive, Assignee.Profile.Name, Assignee.UserRole.Name, ' +
                    'Assignee.LastLoginDate ' +
                    'FROM PermissionSetAssignment ' +
                    'WHERE PermissionSetId IN :matchingPSIds';

                if (activeOnly) {
                    psaQuery += ' AND Assignee.IsActive = true';
                }

                psaQuery += ' ORDER BY Assignee.Name';

                List<PermissionSetAssignment> allPSA = Database.query(psaQuery);

                // Step 6: Filter by profile
                if (profileFilter != 'all') {
                    List<PermissionSetAssignment> filtered = new List<PermissionSetAssignment>();
                    for (PermissionSetAssignment psa : allPSA) {
                        if (psa.Assignee.Profile != null && psa.Assignee.Profile.Name.containsIgnoreCase(profileFilter)) {
                            filtered.add(psa);
                        }
                    }
                    allPSA = filtered;
                }

                // Step 7: Build user results
                Map<Id, Map<String, Object>> userResults = new Map<Id, Map<String, Object>>();

                for (PermissionSetAssignment psa : allPSA) {
                    Id userId = psa.AssigneeId;

                    if (!userResults.containsKey(userId)) {
                        Map<String, Object> userData = new Map<String, Object>();
                        userData.put('name', psa.Assignee.Name);
                        userData.put('username', psa.Assignee.Username);
                        userData.put('email', psa.Assignee.Email);
                        userData.put('isActive', psa.Assignee.IsActive);
                        userData.put('profile', psa.Assignee.Profile != null ? psa.Assignee.Profile.Name : 'N/A');
                        userData.put('role', psa.Assignee.UserRole != null ? psa.Assignee.UserRole.Name : 'N/A');
                        userData.put('lastLogin', psa.Assignee.LastLoginDate != null ? String.valueOf(psa.Assignee.LastLoginDate.date()) : 'NEVER');
                        userData.put('permSources', new List<String>());
                        userResults.put(userId, userData);
                    }

                    PermissionSet ps = psMap.get(psa.PermissionSetId);
                    String sourceName;

                    if (ps != null && ps.IsOwnedByProfile) {
                        String pName = profileNames.containsKey(ps.ProfileId) ? profileNames.get(ps.ProfileId) : ps.Name;
                        sourceName = pName + ' (Profile)';
                    } else {
                        String psLabel = (ps != null && ps.Label != null) ? ps.Label : ((ps != null && ps.Name != null) ? ps.Name : 'Unknown');
                        sourceName = psLabel + ' (Permission Set)';
                    }

                    List<String> sources = (List<String>) userResults.get(userId).get('permSources');
                    if (!sources.contains(sourceName)) {
                        sources.add(sourceName);
                    }
                }

                // Step 8: Build COMPACT Report
                Integer totalUsers = userResults.size();
                String report = '';

                report += 'TOTAL USERS FOUND: ' + totalUsers + '\n\n';

                // Profile breakdown
                Map<String, Integer> profileCounts = new Map<String, Integer>();
                for (Id userId : userResults.keySet()) {
                    String prof = (String) userResults.get(userId).get('profile');
                    Integer cnt = profileCounts.containsKey(prof) ? profileCounts.get(prof) : 0;
                    profileCounts.put(prof, cnt + 1);
                }

                report += 'BY PROFILE:\n';
                for (String prof : profileCounts.keySet()) {
                    report += '  ' + prof + ': ' + profileCounts.get(prof) + '\n';
                }
                report += '\n';

                // Role breakdown
                Map<String, Integer> roleCounts = new Map<String, Integer>();
                for (Id userId : userResults.keySet()) {
                    String role = (String) userResults.get(userId).get('role');
                    Integer cnt = roleCounts.containsKey(role) ? roleCounts.get(role) : 0;
                    roleCounts.put(role, cnt + 1);
                }

                report += 'BY ROLE:\n';
                for (String role : roleCounts.keySet()) {
                    report += '  ' + role + ': ' + roleCounts.get(role) + '\n';
                }
                report += '\n';

                // ALL users compact
                report += 'ALL ' + totalUsers + ' USERS:\n';
                report += '===============\n\n';

                Integer userCount = 0;
                for (Id userId : userResults.keySet()) {
                    if (userCount >= 75) {
                        report += '... and ' + (totalUsers - 75) + ' more users.\n';
                        break;
                    }
                    userCount++;
                    Map<String, Object> user = userResults.get(userId);
                    List<String> sources = (List<String>) user.get('permSources');

                    report += userCount + '. ' + (String) user.get('name') + '\n';
                    report += '   ' + (String) user.get('username') + ' | ' + (String) user.get('email') + '\n';
                    report += '   Profile: ' + (String) user.get('profile');
                    report += ' | Role: ' + (String) user.get('role');
                    report += ' | Last Login: ' + (String) user.get('lastLogin') + '\n';
                    report += '   Via: ';
                    Integer srcCount = 0;
                    for (String src : sources) {
                        if (srcCount >= 3) {
                            report += ' +' + (sources.size() - 3) + ' more';
                            break;
                        }
                        if (srcCount > 0) { report += ', '; }
                        report += src;
                        srcCount++;
                    }
                    report += '\n\n';
                }

                // Step 9: CSV
                String csv = 'Name,Username,Email,Profile,Role,Active,LastLogin,PermissionSources\n';

                for (Id userId : userResults.keySet()) {
                    Map<String, Object> user = userResults.get(userId);
                    List<String> sources = (List<String>) user.get('permSources');

                    String uName = (String) user.get('name');
                    String uUsername = (String) user.get('username');
                    String uEmail = (String) user.get('email');
                    String uProfile = (String) user.get('profile');
                    String uRole = (String) user.get('role');
                    Boolean uActive = (Boolean) user.get('isActive');
                    String uLogin = (String) user.get('lastLogin');
                    String srcStr = String.join(sources, '; ');

                    if (csv.length() < 500000) {
                        csv += '"' + uName + '","' + uUsername + '","' + uEmail + '","' +
                            uProfile + '","' + uRole + '",' + uActive + ',"' + uLogin + '","' +
                            srcStr + '"\n';
                    }
                }

                output.reportResult = report;
                output.totalUsers = totalUsers;
                output.csvData = csv;

            } catch (Exception e) {
                output.reportResult = 'Error: ' + e.getMessage() + '\n' + e.getStackTraceString();
                output.totalUsers = 0;
                output.csvData = '';
            }

            outputs.add(output);
        }
        return outputs;
    }
}