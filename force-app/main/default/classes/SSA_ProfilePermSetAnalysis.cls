public with sharing class SSA_ProfilePermSetAnalysis {

    // REQUEST / RESPONSE WRAPPERS
  

    public class ActionInput {
        @InvocableVariable(label='Analysis Type' 
            description='user_profiles, user_permsets, user_psgs, or all')
        public String analysisType;

        @InvocableVariable(label='Name Filter' 
            description='Specific name to search or all')
        public String nameFilter;
    }

    public class ActionOutput {
        @InvocableVariable(label='CSV File URL')
        public String csvFileUrl;

        @InvocableVariable(label='CSV File ID')
        public String csvFileId;

        @InvocableVariable(label='File Name')
        public String fileName;

        @InvocableVariable(label='Record Count')
        public Integer recordCount;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Summary')
        public String summary;

        @InvocableVariable(label='Used Items')
        public String usedItems;

        @InvocableVariable(label='Unused Items')
        public String unusedItems;

        @InvocableVariable(label='Total Profiles')
        public Integer totalProfiles;

        @InvocableVariable(label='Total Permission Sets')
        public Integer totalPermSets;

        @InvocableVariable(label='Total Permission Set Groups')
        public Integer totalPSGroups;

        @InvocableVariable(label='Unused Profiles Count')
        public Integer unusedProfilesCount;

        @InvocableVariable(label='Unused Permission Sets Count')
        public Integer unusedPermSetsCount;

        @InvocableVariable(label='Unused PSGs Count')
        public Integer unusedPSGsCount;
    }

    @InvocableMethod(
        label='SSA Profile and PermSet Analysis'
        description='Analyzes users joined with profiles, permission sets, and PSGs. Returns summary counts and a downloadable CSV file with full user details.'
        category='SSA Org Analyzer'
    )
    public static List<ActionOutput> run(List<ActionInput> inputs) {
        List<ActionOutput> outputs = new List<ActionOutput>();

        for (ActionInput input : inputs) {
            ActionOutput output = new ActionOutput();

            try {
                String analysisType = (input.analysisType != null) 
                    ? input.analysisType.trim().toLowerCase() 
                    : 'all';
                String nameFilter = (input.nameFilter != null) 
                    ? input.nameFilter.trim() 
                    : 'all';

                String csv = '';
                Integer totalRows = 0;
                String summaryAll = '';
                String usedAll = '';
                String unusedAll = '';

                if (analysisType == 'user_profiles' || analysisType == 'all') {
                    Map<String, Object> result = buildUserProfiles(nameFilter);
                    csv += (String) result.get('csv');
                    totalRows += (Integer) result.get('rows');
                    output.totalProfiles = (Integer) result.get('totalProfiles');
                    output.unusedProfilesCount = (Integer) result.get('unusedProfiles');
                    summaryAll += (String) result.get('summaryText');
                    usedAll += (String) result.get('usedText');
                    unusedAll += (String) result.get('unusedText');
                }

                if (analysisType == 'user_permsets' || analysisType == 'all') {
                    Map<String, Object> result = buildUserPermSets(nameFilter);
                    if (analysisType == 'all') {
                        csv += '\n\n--- USERS + PERMISSION SETS ---\n';
                        if (summaryAll != '') summaryAll += ' | ';
                        if (usedAll != '') usedAll += ' | ';
                        if (unusedAll != '') unusedAll += ' | ';
                    } else {
                        csv = '';
                    }
                    csv += (String) result.get('csv');
                    totalRows += (Integer) result.get('rows');
                    output.totalPermSets = (Integer) result.get('totalPS');
                    output.unusedPermSetsCount = (Integer) result.get('unusedPS');
                    summaryAll += (String) result.get('summaryText');
                    usedAll += (String) result.get('usedText');
                    unusedAll += (String) result.get('unusedText');
                }

                if (analysisType == 'user_psgs' || analysisType == 'all') {
                    Map<String, Object> result = buildUserPSGs(nameFilter);
                    if (analysisType == 'all') {
                        csv += '\n\n--- USERS + PERMISSION SET GROUPS ---\n';
                        if (summaryAll != '') summaryAll += ' | ';
                        if (usedAll != '') usedAll += ' | ';
                        if (unusedAll != '') unusedAll += ' | ';
                    } else {
                        csv = '';
                    }
                    csv += (String) result.get('csv');
                    totalRows += (Integer) result.get('rows');
                    output.totalPSGroups = (Integer) result.get('totalPSG');
                    output.unusedPSGsCount = (Integer) result.get('unusedPSG');
                    summaryAll += (String) result.get('summaryText');
                    usedAll += (String) result.get('usedText');
                    unusedAll += (String) result.get('unusedText');
                }

                output.summary = summaryAll;
                output.usedItems = usedAll;
                output.unusedItems = unusedAll;
                output.recordCount = totalRows;

                // Inline file creation  
                if (String.isNotBlank(csv) && totalRows > 0) {
                    ContentVersion cv = generateCSVFile(csv, analysisType, nameFilter);
                    
                    output.csvFileId = cv.ContentDocumentId;
                    output.fileName = cv.Title;
                    output.csvFileUrl = URL.getOrgDomainUrl().toExternalForm() 
                                      + '/sfc/servlet.shepherd/document/download/' 
                                      + cv.ContentDocumentId;
                    output.message = ' CSV file generated successfully with ' + totalRows + ' rows.';
                } else {
                    output.csvFileId = '';
                    output.csvFileUrl = '';
                    output.fileName = '';
                    output.message = 'No data found — no file generated.';
                    output.recordCount = 0;
                }

            } catch (Exception e) {
                output.message = ' Error: ' + e.getMessage();
                output.summary = 'Error: ' + e.getMessage();
                output.usedItems = '';
                output.unusedItems = '';
                output.recordCount = 0;
                output.totalProfiles = 0;
                output.totalPermSets = 0;
                output.totalPSGroups = 0;
                output.unusedProfilesCount = 0;
                output.unusedPermSetsCount = 0;
                output.unusedPSGsCount = 0;
                output.csvFileId = '';
                output.csvFileUrl = '';
                output.fileName = '';
            }

            outputs.add(output);
        }
        return outputs;
    }


    // HELPER: GENERATE CSV FILE  
   
    private static ContentVersion generateCSVFile(String csv, String analysisType, String nameFilter) {
        String fileName = 'SSA_' + analysisType + '_' + nameFilter + '_' 
                        + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';

        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf(csv);
        cv.Description = 'SSA ' + analysisType + ' Analysis | Filter: ' + nameFilter;
        cv.IsMajorVersion = true;
        insert cv;

        cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];

        ContentDocumentLink cdl = new ContentDocumentLink();
        cdl.ContentDocumentId = cv.ContentDocumentId;
        cdl.LinkedEntityId = UserInfo.getUserId();
        cdl.ShareType = 'V';
        cdl.Visibility = 'AllUsers';
        try { 
            insert cdl; 
        } catch (Exception e) {
            // Ignore if already linked
        }

        return cv;
    }

    private static String safe(String val) {
        if (val == null || val == '') return '';
        return val.replace('"', '""');
    }

    // buildUserProfiles
   
    private static Map<String, Object> buildUserProfiles(String nameFilter) {

        Map<Id, String> profileNames = new Map<Id, String>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            profileNames.put(p.Id, p.Name);
        }

        List<AggregateResult> activeAgg = [
            SELECT ProfileId, COUNT(Id) cnt FROM User WHERE IsActive = true GROUP BY ProfileId
        ];
        List<AggregateResult> inactiveAgg = [
            SELECT ProfileId, COUNT(Id) cnt FROM User WHERE IsActive = false GROUP BY ProfileId
        ];

        Map<Id, Integer> activeCountMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveCountMap = new Map<Id, Integer>();

        for (AggregateResult ar : activeAgg) {
            activeCountMap.put((Id) ar.get('ProfileId'), (Integer) ar.get('cnt'));
        }
        for (AggregateResult ar : inactiveAgg) {
            inactiveCountMap.put((Id) ar.get('ProfileId'), (Integer) ar.get('cnt'));
        }

        Set<Id> profileIds = profileNames.keySet();

        Set<Id> matchingProfileIds = new Set<Id>();
        if (nameFilter != 'all') {
            for (Profile p : [SELECT Id FROM Profile WHERE Name LIKE :('%' + nameFilter + '%')]) {
                matchingProfileIds.add(p.Id);
            }
        }

        String query = 'SELECT Username, Name, Email, ProfileId, IsActive, ' +
            'LastLoginDate, CreatedDate, UserType ' +
            'FROM User WHERE ProfileId IN :profileIds ';

        if (nameFilter != 'all') {
            query += 'AND (ProfileId IN :matchingProfileIds ' +
                'OR Name LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\') ';
        }
        query += 'ORDER BY Username';

        List<User> users = Database.query(query);

        String csv = 'SECTION,PROFILE_NAME,PROFILE_ID,ACTIVE_USERS,INACTIVE_USERS,TOTAL_USERS\n';

        List<Id> sortedProfileIds = new List<Id>();
        Map<Id, String> idToName = new Map<Id, String>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            sortedProfileIds.add(p.Id);
            idToName.put(p.Id, p.Name);
        }

        Set<Id> usedProfileIds = new Set<Id>();
        Integer totalActiveUsers = 0;
        Integer totalInactiveUsers = 0;

        for (Id profId : sortedProfileIds) {
            String profName = idToName.get(profId);
            if (nameFilter != 'all' && !profName.containsIgnoreCase(nameFilter)) continue;
            Integer active = activeCountMap.containsKey(profId) ? activeCountMap.get(profId) : 0;
            Integer inactive = inactiveCountMap.containsKey(profId) ? inactiveCountMap.get(profId) : 0;
            Integer total = active + inactive;
            if (total > 0) {
                usedProfileIds.add(profId);
                totalActiveUsers += active;
                totalInactiveUsers += inactive;
                csv += '"PROFILE_SUMMARY","' + safe(profName) + '",' + profId + ',' +
                    active + ',' + inactive + ',' + total + '\n';
            }
        }

        List<String> unusedProfileNamesList = new List<String>();
        for (Id profId : sortedProfileIds) {
            String profName = idToName.get(profId);
            if (nameFilter != 'all' && !profName.containsIgnoreCase(nameFilter)) continue;
            Integer active = activeCountMap.containsKey(profId) ? activeCountMap.get(profId) : 0;
            Integer inactive = inactiveCountMap.containsKey(profId) ? inactiveCountMap.get(profId) : 0;
            if (active == 0 && inactive == 0) {
                unusedProfileNamesList.add(profName);
                csv += '"UNUSED_PROFILE","' + safe(profName) + '",' + profId + ',0,0,0\n';
            }
        }

        csv += '\n--- USER DETAILS ---\n';
        csv += 'SECTION,USERNAME,FULL_NAME,EMAIL,PROFILE_NAME,PROFILE_ID,' +
            'ISACTIVE,USER_TYPE,LAST_LOGIN,CREATED_DATE\n';

        Integer userRows = 0;
        for (User u : users) {
            String profName = profileNames.containsKey(u.ProfileId) ? profileNames.get(u.ProfileId) : '';
            if (profName == '') continue;
            String lastLogin = (u.LastLoginDate != null) ? String.valueOf(u.LastLoginDate.date()) : 'NEVER';
            String created = String.valueOf(u.CreatedDate.date());
            String userType = (u.UserType != null) ? u.UserType : '';
            if (csv.length() < 5000000) {
                csv += '"USER","' + safe(u.Username) + '","' +
                    safe(u.Name) + '","' +
                    safe(u.Email) + '","' +
                    safe(profName) + '",' +
                    u.ProfileId + ',' +
                    u.IsActive + ',"' +
                    safe(userType) + '","' +
                    lastLogin + '","' +
                    created + '"\n';
            }
            userRows++;
        }

        Integer totalProfiles = profileNames.size();
        Integer unusedCount = unusedProfileNamesList.size();

        String summaryText = 'Profile Summary: ' +
            'Total Unique Profiles: ' + totalProfiles +
            ', Profiles with Users: ' + usedProfileIds.size() +
            ', Unused Profiles: ' + unusedCount +
            ', Active Users: ' + totalActiveUsers +
            ', Inactive Users: ' + totalInactiveUsers;

        String usedText = '';
        for (Id profId : sortedProfileIds) {
            String profName = idToName.get(profId);
            if (nameFilter != 'all' && !profName.containsIgnoreCase(nameFilter)) continue;
            Integer active = activeCountMap.containsKey(profId) ? activeCountMap.get(profId) : 0;
            Integer inactive = inactiveCountMap.containsKey(profId) ? inactiveCountMap.get(profId) : 0;
            Integer total = active + inactive;
            if (total > 0) {
                if (usedText != '') usedText += ', ';
                usedText += profName + ': ' + total + ' users (' + active + ' active ' + inactive + ' inactive)';
            }
        }

        String unusedText = String.join(unusedProfileNamesList, ', ');

        return new Map<String, Object>{
            'csv' => csv,
            'rows' => userRows,
            'totalProfiles' => totalProfiles,
            'unusedProfiles' => unusedCount,
            'summaryText' => summaryText,
            'usedText' => usedText,
            'unusedText' => unusedText
        };
    }

    // buildUserPermSets
   
    private static Map<String, Object> buildUserPermSets(String nameFilter) {

        List<PermissionSet> allPS = [
            SELECT Id, Name, Label, Type, NamespacePrefix, CreatedDate
            FROM PermissionSet
            WHERE IsOwnedByProfile = false AND Type != 'Group'
            ORDER BY Label
        ];

        Integer totalPS = allPS.size();

        List<AggregateResult> activeAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt
            FROM PermissionSetAssignment
            WHERE PermissionSet.IsOwnedByProfile = false
            AND PermissionSet.Type != 'Group'
            AND Assignee.IsActive = true
            GROUP BY PermissionSetId
        ];

        List<AggregateResult> inactiveAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt
            FROM PermissionSetAssignment
            WHERE PermissionSet.IsOwnedByProfile = false
            AND PermissionSet.Type != 'Group'
            AND Assignee.IsActive = false
            GROUP BY PermissionSetId
        ];

        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveMap = new Map<Id, Integer>();

        for (AggregateResult ar : activeAgg) {
            activeMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt'));
        }
        for (AggregateResult ar : inactiveAgg) {
            inactiveMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt'));
        }

        Map<Id, List<String>> psIdToPSGNames = new Map<Id, List<String>>();
        Set<Id> psIdsInPSGs = new Set<Id>();

        for (PermissionSetGroupComponent comp : [
            SELECT PermissionSetId, PermissionSetGroup.DeveloperName, PermissionSetGroup.MasterLabel
            FROM PermissionSetGroupComponent
        ]) {
            psIdsInPSGs.add(comp.PermissionSetId);
            if (!psIdToPSGNames.containsKey(comp.PermissionSetId)) {
                psIdToPSGNames.put(comp.PermissionSetId, new List<String>());
            }
            String psgLabel = (comp.PermissionSetGroup.MasterLabel != null) ?
                comp.PermissionSetGroup.MasterLabel : comp.PermissionSetGroup.DeveloperName;
            psIdToPSGNames.get(comp.PermissionSetId).add(psgLabel);
        }

        Map<Id, PermissionSet> psgPSMap = new Map<Id, PermissionSet>([
            SELECT Id, Name, Label FROM PermissionSet WHERE Type = 'Group'
        ]);
        Set<Id> psgPSIds = psgPSMap.keySet();

        Map<String, Id> psgNameToCompanionId = new Map<String, Id>();
        for (PermissionSetGroup psg : [SELECT Id, DeveloperName, MasterLabel FROM PermissionSetGroup]) {
            for (PermissionSet ps : psgPSMap.values()) {
                if (ps.Name == psg.DeveloperName || ps.Label == psg.MasterLabel) {
                    psgNameToCompanionId.put(psg.DeveloperName, ps.Id);
                    if (psg.MasterLabel != null) psgNameToCompanionId.put(psg.MasterLabel, ps.Id);
                }
            }
        }

        Map<Id, Set<Id>> userPSGAssignments = new Map<Id, Set<Id>>();
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, PermissionSetId
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :psgPSIds
        ]) {
            if (!userPSGAssignments.containsKey(psa.AssigneeId)) {
                userPSGAssignments.put(psa.AssigneeId, new Set<Id>());
            }
            userPSGAssignments.get(psa.AssigneeId).add(psa.PermissionSetId);
        }

        String csv = 'SECTION,PS_NAME,PS_LABEL,PS_ID,ACTIVE_USERS,INACTIVE_USERS,TOTAL_USERS\n';

        List<String> usedPSReport = new List<String>();
        List<String> unusedPSReport = new List<String>();
        Integer usedCount = 0;
        Integer unusedCount = 0;

        for (PermissionSet ps : allPS) {
            String label = (ps.Label != null) ? ps.Label : ps.Name;
            if (nameFilter != 'all' && !label.containsIgnoreCase(nameFilter) &&
                (ps.Name == null || !ps.Name.containsIgnoreCase(nameFilter))) continue;

            Integer active = activeMap.containsKey(ps.Id) ? activeMap.get(ps.Id) : 0;
            Integer inactive = inactiveMap.containsKey(ps.Id) ? inactiveMap.get(ps.Id) : 0;
            Integer total = active + inactive;

            if (total > 0) {
                usedCount++;
                csv += '"PS_SUMMARY","' + safe(ps.Name) + '","' + safe(label) + '",' +
                    ps.Id + ',' + active + ',' + inactive + ',' + total + '\n';
                usedPSReport.add(label + ': ' + total + ' users (' + active + ' active ' + inactive + ' inactive)');
            } else {
                unusedCount++;
                csv += '"UNUSED_PS","' + safe(ps.Name) + '","' + safe(label) + '",' +
                    ps.Id + ',0,0,0\n';
                unusedPSReport.add(label);
            }
        }

        String detailQuery = 'SELECT ' +
            'Assignee.Username, Assignee.Name, Assignee.Email, ' +
            'Assignee.IsActive, Assignee.Profile.Name, Assignee.UserType, ' +
            'AssigneeId, ' +
            'PermissionSet.Name, PermissionSet.Label, ' +
            'PermissionSetId ' +
            'FROM PermissionSetAssignment ' +
            'WHERE PermissionSet.IsOwnedByProfile = false ' +
            'AND PermissionSet.Type != \'Group\' ';

        if (nameFilter != 'all') {
            detailQuery += 'AND (PermissionSet.Label LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\' ' +
                'OR PermissionSet.Name LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\' ' +
                'OR Assignee.Name LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\') ';
        }

        detailQuery += 'ORDER BY PermissionSet.Label, Assignee.Username';

        List<PermissionSetAssignment> allPSA = Database.query(detailQuery);

        csv += '\n--- USER DETAILS ---\n';
        csv += 'SECTION,USERNAME,FULL_NAME,EMAIL,USER_PROFILE,ISACTIVE,USER_TYPE,' +
            'PS_NAME,PS_LABEL,PS_ID,ASSIGNED_VIA,PSG_NAMES\n';

        Integer userRows = 0;
        Integer directCount = 0;
        Integer viaPSGCount = 0;

        for (PermissionSetAssignment psa : allPSA) {
            String psLabel = (psa.PermissionSet.Label != null) ? psa.PermissionSet.Label : psa.PermissionSet.Name;
            String userProfile = (psa.Assignee.Profile != null) ? psa.Assignee.Profile.Name : '';
            String userType = (psa.Assignee.UserType != null) ? psa.Assignee.UserType : '';

            Id psId = psa.PermissionSetId;
            Id userId = psa.AssigneeId;

            Boolean assignedViaPSG = false;
            List<String> matchedPSGNames = new List<String>();

            if (psIdsInPSGs.contains(psId) && psIdToPSGNames.containsKey(psId)) {
                List<String> potentialPSGs = psIdToPSGNames.get(psId);
                Set<Id> userPSGs = userPSGAssignments.containsKey(userId) ?
                    userPSGAssignments.get(userId) : new Set<Id>();

                for (String psgName : potentialPSGs) {
                    Id companionId = psgNameToCompanionId.get(psgName);
                    if (companionId != null && userPSGs.contains(companionId)) {
                        assignedViaPSG = true;
                        matchedPSGNames.add(psgName);
                    }
                }
            }

            String assignedVia;
            String psgNamesStr = '';

            if (assignedViaPSG) {
                assignedVia = 'Via PSG';
                psgNamesStr = String.join(matchedPSGNames, '; ');
                viaPSGCount++;
            } else {
                assignedVia = 'Direct';
                directCount++;
            }

            if (csv.length() < 5000000) {
                csv += '"USER","' + safe(psa.Assignee.Username) + '","' +
                    safe(psa.Assignee.Name) + '","' +
                    safe(psa.Assignee.Email) + '","' +
                    safe(userProfile) + '",' +
                    psa.Assignee.IsActive + ',"' +
                    safe(userType) + '","' +
                    safe(psa.PermissionSet.Name) + '","' +
                    safe(psLabel) + '",' +
                    psa.PermissionSetId + ',"' +
                    assignedVia + '","' +
                    safe(psgNamesStr) + '"\n';
            }
            userRows++;
        }

        String summaryText = 'Permission Set Summary: ' +
            'Total Unique Permission Sets: ' + totalPS +
            ', With Users: ' + usedCount +
            ', Unused: ' + unusedCount +
            ', Total Assignments: ' + userRows +
            ', Direct: ' + directCount +
            ', Via PSG: ' + viaPSGCount;

        String usedText = String.join(usedPSReport, ', ');
        String unusedText = String.join(unusedPSReport, ', ');

        return new Map<String, Object>{
            'csv' => csv,
            'rows' => userRows,
            'totalPS' => totalPS,
            'unusedPS' => unusedCount,
            'summaryText' => summaryText,
            'usedText' => usedText,
            'unusedText' => unusedText
        };
    }


    // buildUserPSGs
  
    private static Map<String, Object> buildUserPSGs(String nameFilter) {

        Map<Id, PermissionSetGroup> psgMap = new Map<Id, PermissionSetGroup>([
            SELECT Id, DeveloperName, MasterLabel, Status, CreatedDate
            FROM PermissionSetGroup
            ORDER BY MasterLabel
        ]);

        Integer totalPSG = psgMap.size();

        Map<Id, PermissionSet> psgPSMap = new Map<Id, PermissionSet>([
            SELECT Id, Name, Label FROM PermissionSet WHERE Type = 'Group'
        ]);

        Set<Id> psgPSIds = psgPSMap.keySet();

        Map<String, Id> psNameToPSGId = new Map<String, Id>();
        for (PermissionSetGroup psg : psgMap.values()) {
            psNameToPSGId.put(psg.DeveloperName, psg.Id);
            if (psg.MasterLabel != null) psNameToPSGId.put(psg.MasterLabel, psg.Id);
        }

        Map<Id, List<String>> psgComponents = new Map<Id, List<String>>();
        for (PermissionSetGroupComponent comp : [
            SELECT PermissionSetGroupId, PermissionSet.Label, PermissionSet.Name
            FROM PermissionSetGroupComponent
        ]) {
            if (!psgComponents.containsKey(comp.PermissionSetGroupId)) {
                psgComponents.put(comp.PermissionSetGroupId, new List<String>());
            }
            String compLabel = (comp.PermissionSet.Label != null) ? comp.PermissionSet.Label : comp.PermissionSet.Name;
            psgComponents.get(comp.PermissionSetGroupId).add(compLabel);
        }

        List<AggregateResult> activeAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :psgPSIds AND Assignee.IsActive = true
            GROUP BY PermissionSetId
        ];

        List<AggregateResult> inactiveAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :psgPSIds AND Assignee.IsActive = false
            GROUP BY PermissionSetId
        ];

        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveMap = new Map<Id, Integer>();

        for (AggregateResult ar : activeAgg) {
            activeMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt'));
        }
        for (AggregateResult ar : inactiveAgg) {
            inactiveMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt'));
        }

        Map<Id, Id> companionToPSGId = new Map<Id, Id>();
        for (PermissionSet ps : psgPSMap.values()) {
            Id psgId = psNameToPSGId.containsKey(ps.Name) ? psNameToPSGId.get(ps.Name) :
                (ps.Label != null && psNameToPSGId.containsKey(ps.Label) ? psNameToPSGId.get(ps.Label) : null);
            if (psgId != null) {
                companionToPSGId.put(ps.Id, psgId);
            }
        }

        String csv = 'SECTION,PSG_NAME,PSG_LABEL,PSG_ID,NUM_PS_INSIDE,' +
            'CONTAINED_PS,ACTIVE_USERS,INACTIVE_USERS,TOTAL_USERS\n';

        List<String> usedPSGReport = new List<String>();
        List<String> unusedPSGReport = new List<String>();
        Set<Id> usedPSGIds = new Set<Id>();
        Integer usedCount = 0;
        Integer unusedCount = 0;

        for (Id companionId : psgPSMap.keySet()) {
            Id psgId = companionToPSGId.get(companionId);
            if (psgId == null) continue;

            PermissionSetGroup psg = psgMap.get(psgId);
            if (psg == null) continue;

            String label = (psg.MasterLabel != null) ? psg.MasterLabel : psg.DeveloperName;
            if (nameFilter != 'all' && !label.containsIgnoreCase(nameFilter) &&
                !psg.DeveloperName.containsIgnoreCase(nameFilter)) continue;

            Integer active = activeMap.containsKey(companionId) ? activeMap.get(companionId) : 0;
            Integer inactive = inactiveMap.containsKey(companionId) ? inactiveMap.get(companionId) : 0;
            Integer total = active + inactive;

            List<String> components = psgComponents.containsKey(psgId) ?
                psgComponents.get(psgId) : new List<String>();
            Integer numPS = components.size();
            String componentStr = String.join(components, '; ');

            if (total > 0) {
                usedCount++;
                usedPSGIds.add(psgId);
                csv += '"PSG_SUMMARY","' + safe(psg.DeveloperName) + '","' + safe(label) + '",' +
                    psgId + ',' + numPS + ',"' + safe(componentStr) + '",' +
                    active + ',' + inactive + ',' + total + '\n';
                usedPSGReport.add(label + ': ' + total + ' users (' + active + ' active ' + inactive + ' inactive)');
            }
        }

        for (PermissionSetGroup psg : psgMap.values()) {
            if (usedPSGIds.contains(psg.Id)) continue;

            String label = (psg.MasterLabel != null) ? psg.MasterLabel : psg.DeveloperName;
            if (nameFilter != 'all' && !label.containsIgnoreCase(nameFilter) &&
                !psg.DeveloperName.containsIgnoreCase(nameFilter)) continue;

            List<String> components = psgComponents.containsKey(psg.Id) ?
                psgComponents.get(psg.Id) : new List<String>();
            Integer numPS = components.size();
            String componentStr = String.join(components, '; ');

            unusedCount++;
            csv += '"UNUSED_PSG","' + safe(psg.DeveloperName) + '","' + safe(label) + '",' +
                psg.Id + ',' + numPS + ',"' + safe(componentStr) + '",0,0,0\n';
            unusedPSGReport.add(label);
        }

        String detailQuery = 'SELECT ' +
            'Assignee.Username, Assignee.Name, Assignee.Email, ' +
            'Assignee.IsActive, Assignee.Profile.Name, Assignee.UserType, ' +
            'PermissionSet.Name, PermissionSet.Label, ' +
            'PermissionSetId ' +
            'FROM PermissionSetAssignment ' +
            'WHERE PermissionSetId IN :psgPSIds ';

        if (nameFilter != 'all') {
            detailQuery += 'AND (PermissionSet.Label LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\' ' +
                'OR PermissionSet.Name LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\' ' +
                'OR Assignee.Name LIKE \'%' + String.escapeSingleQuotes(nameFilter) + '%\') ';
        }

        detailQuery += 'ORDER BY PermissionSet.Label, Assignee.Username';

        List<PermissionSetAssignment> allPSA = Database.query(detailQuery);

        csv += '\n--- USER DETAILS ---\n';
        csv += 'SECTION,USERNAME,FULL_NAME,EMAIL,USER_PROFILE,ISACTIVE,USER_TYPE,' +
            'PSG_NAME,PSG_LABEL,PSG_ID\n';

        Integer userRows = 0;
        for (PermissionSetAssignment psa : allPSA) {
            String psName = psa.PermissionSet.Name;
            String psLabel = (psa.PermissionSet.Label != null) ? psa.PermissionSet.Label : psName;

            Id psgId = psNameToPSGId.containsKey(psName) ? psNameToPSGId.get(psName) :
                (psNameToPSGId.containsKey(psLabel) ? psNameToPSGId.get(psLabel) : null);
            PermissionSetGroup psg = (psgId != null) ? psgMap.get(psgId) : null;

            String psgLabel = (psg != null && psg.MasterLabel != null) ? psg.MasterLabel : psLabel;
            String psgName = (psg != null) ? psg.DeveloperName : psName;
            String psgIdStr = (psg != null) ? String.valueOf(psg.Id) : '';

            String userProfile = (psa.Assignee.Profile != null) ? psa.Assignee.Profile.Name : '';
            String userType = (psa.Assignee.UserType != null) ? psa.Assignee.UserType : '';

            if (csv.length() < 5000000) {
                csv += '"USER","' + safe(psa.Assignee.Username) + '","' +
                    safe(psa.Assignee.Name) + '","' +
                    safe(psa.Assignee.Email) + '","' +
                    safe(userProfile) + '",' +
                    psa.Assignee.IsActive + ',"' +
                    safe(userType) + '","' +
                    safe(psgName) + '","' +
                    safe(psgLabel) + '","' +
                    safe(psgIdStr) + '"\n';
            }
            userRows++;
        }

        String summaryText = 'Permission Set Group Summary: ' +
            'Total PSGs: ' + totalPSG +
            ', With Users: ' + usedCount +
            ', Unused: ' + unusedCount +
            ', Total Assignments: ' + userRows;

        String usedText = String.join(usedPSGReport, ', ');
        String unusedText = String.join(unusedPSGReport, ', ');

        return new Map<String, Object>{
            'csv' => csv,
            'rows' => userRows,
            'totalPSG' => totalPSG,
            'unusedPSG' => unusedCount,
            'summaryText' => summaryText,
            'usedText' => usedText,
            'unusedText' => unusedText
        };
    }
}