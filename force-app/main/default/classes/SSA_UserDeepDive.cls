public with sharing class SSA_UserDeepDive {

    //  INPUT / OUTPUT 

    public class DeepDiveInput {
        @InvocableVariable(label='User Identifier' required=true
            description='User ID (005...), Username, Email, or Full Name to look up')
        public String userIdentifier;
    }

    public class DeepDiveOutput {
        // User Basic Info
        @InvocableVariable public String userFullName;
        @InvocableVariable public String username;
        @InvocableVariable public String email;
        @InvocableVariable public String userId;
        @InvocableVariable public String profileName;
        @InvocableVariable public String roleName;
        @InvocableVariable public String userType;
        @InvocableVariable public Boolean isActive;
        @InvocableVariable public String lastLogin;
        @InvocableVariable public String createdDate;
        @InvocableVariable public Integer daysSinceLogin;

        // Access Summary
        @InvocableVariable public Integer totalPermissionSets;
        @InvocableVariable public Integer directPermissionSets;
        @InvocableVariable public Integer viaPSGPermissionSets;
        @InvocableVariable public Integer totalPSGs;
        @InvocableVariable public Integer totalObjectsWithAccess;
        @InvocableVariable public Integer modifyAllCount;
        @InvocableVariable public Integer viewAllCount;
        @InvocableVariable public Integer fullCrudCount;

        // Details
        @InvocableVariable public String permissionSetsList;
        @InvocableVariable public String psgsList;
        @InvocableVariable public String topObjectsAccess;

        // File Outputs
        @InvocableVariable public String csvFileUrl;
        @InvocableVariable public String csvFileId;
        @InvocableVariable public String fileName;
        @InvocableVariable public String message;
    }

    // ENTRY POINT 

    @InvocableMethod(
        label='SSA User Deep Dive'
        description='Returns comprehensive information about a single user including profile, permission sets, PSGs, object access, and a downloadable detailed CSV.'
        category='SSA Org Analyzer'
    )
    public static List<DeepDiveOutput> run(List<DeepDiveInput> inputs) {
        List<DeepDiveOutput> outputs = new List<DeepDiveOutput>();

        Set<String> vagueTerms = new Set<String>{
            'more', 'tell me more', 'continue', 'expand',
            'details', 'info', 'yes', 'ok', 'next', 'go on'
        };

        for (DeepDiveInput input : inputs) {
            DeepDiveOutput output = new DeepDiveOutput();

            try {
                String identifier = (input.userIdentifier != null)
                    ? input.userIdentifier.trim() : '';

                if (String.isBlank(identifier)) {
                    output.message = ' User identifier is required.';
                    outputs.add(output);
                    continue;
                }

                if (vagueTerms.contains(identifier.toLowerCase())) {
                    output.message =   identifier + '" is too vague. Please provide a specific name, email, username, or User ID.';
                    outputs.add(output);
                    continue;
                }

                User targetUser = findUser(identifier);
                if (targetUser == null) {
                    output.message = ' No user found matching: ' + identifier;
                    outputs.add(output);
                    continue;
                }

                // Basic info
                output.userFullName = targetUser.Name;
                output.username     = targetUser.Username;
                output.email        = targetUser.Email;
                output.userId       = targetUser.Id;
                output.profileName  = (targetUser.Profile != null) ? targetUser.Profile.Name : 'N/A';
                output.roleName     = (targetUser.UserRole != null) ? targetUser.UserRole.Name : 'N/A';
                output.userType     = targetUser.UserType;
                output.isActive     = targetUser.IsActive;
                output.createdDate  = String.valueOf(targetUser.CreatedDate.date());

                if (targetUser.LastLoginDate != null) {
                    output.lastLogin       = String.valueOf(targetUser.LastLoginDate.date());
                    output.daysSinceLogin  = targetUser.LastLoginDate.date().daysBetween(Date.today());
                } else {
                    output.lastLogin       = 'NEVER';
                    output.daysSinceLogin  = 9999;
                }

                // Permission sets & PSGs
                PermissionSetInfo psInfo = getPermissionSets(targetUser.Id, targetUser.ProfileId);

                output.totalPermissionSets  = psInfo.directCount + psInfo.viaPSGCount;
                output.directPermissionSets = psInfo.directCount;
                output.viaPSGPermissionSets = psInfo.viaPSGCount;
                output.totalPSGs            = psInfo.psgCount;
                output.permissionSetsList   = psInfo.psList;
                output.psgsList             = psInfo.psgList;

                // Object access
                ObjectAccessInfo objInfo = getObjectAccess(psInfo.allPSIdsForAccess);
                output.totalObjectsWithAccess = objInfo.totalObjects;
                output.modifyAllCount         = objInfo.modifyAllCount;
                output.viewAllCount           = objInfo.viewAllCount;
                output.fullCrudCount          = objInfo.fullCrudCount;
                output.topObjectsAccess       = objInfo.topObjectsText;

                // CSV file
                String csv = generateUserCSV(output, psInfo, objInfo);
                ContentVersion cv = createFile(csv, targetUser.Username, targetUser.Id);

                output.csvFileId  = cv.ContentDocumentId;
                output.fileName   = cv.Title;
                output.csvFileUrl = URL.getOrgDomainUrl().toExternalForm()
                                 + '/sfc/servlet.shepherd/document/download/'
                                 + cv.ContentDocumentId;
                output.message    = 'User deep dive complete.';

            } catch (Exception e) {
                output.message     = ' Error: ' + e.getMessage();
                output.csvFileUrl  = '';
                output.csvFileId   = '';
            }

            outputs.add(output);
        }
        return outputs;
    }

    // FIND USER  
    private static User findUser(String identifier) {
        List<User> users;

        if (identifier.startsWith('005') && identifier.length() >= 15) {
            try {
                users = [
                    SELECT Id, Name, Username, Email, IsActive, UserType,
                        ProfileId, Profile.Name, UserRoleId, UserRole.Name,
                        LastLoginDate, CreatedDate
                    FROM User WHERE Id = :identifier LIMIT 1
                ];
                if (!users.isEmpty()) return users[0];
            } catch (Exception e) { }
        }

        users = [
            SELECT Id, Name, Username, Email, IsActive, UserType,
                ProfileId, Profile.Name, UserRoleId, UserRole.Name,
                LastLoginDate, CreatedDate
            FROM User WHERE Username = :identifier LIMIT 1
        ];
        if (!users.isEmpty()) return users[0];

        users = [
            SELECT Id, Name, Username, Email, IsActive, UserType,
                ProfileId, Profile.Name, UserRoleId, UserRole.Name,
                LastLoginDate, CreatedDate
            FROM User WHERE Email = :identifier LIMIT 1
        ];
        if (!users.isEmpty()) return users[0];

        String pattern = '%' + identifier + '%';
        users = [
            SELECT Id, Name, Username, Email, IsActive, UserType,
                ProfileId, Profile.Name, UserRoleId, UserRole.Name,
                LastLoginDate, CreatedDate
            FROM User
            WHERE Name LIKE :pattern
               OR Username LIKE :pattern
               OR Email LIKE :pattern
            ORDER BY IsActive DESC, LastLoginDate DESC NULLS LAST
            LIMIT 1
        ];
        return users.isEmpty() ? null : users[0];
    }

    //  PERMISSION SETS & PSGs 

    private class PermissionSetInfo {
        Integer directCount = 0;
        Integer viaPSGCount = 0;
        Integer psgCount = 0;
        String psList = '';
        String psgList = '';
        Set<Id> allPSIdsForAccess = new Set<Id>();
        List<String> psDetails = new List<String>();
        List<String> psgDetails = new List<String>();
    }

    private static PermissionSetInfo getPermissionSets(Id userId, Id profileId) {
        PermissionSetInfo info = new PermissionSetInfo();

        // 1) Add profile PS so its ObjectPermissions are included
        if (profileId != null) {
            List<PermissionSet> profilePS = [
                SELECT Id FROM PermissionSet
                WHERE IsOwnedByProfile = true AND ProfileId = :profileId
                LIMIT 1
            ];
            if (!profilePS.isEmpty()) info.allPSIdsForAccess.add(profilePS[0].Id);
        }

        // 2) User's PSG assignments
        Set<Id> userPSGIds = new Set<Id>();
        Map<Id, String> psgIdToLabel = new Map<Id, String>();

        for (PermissionSetAssignment psa : [
            SELECT PermissionSetGroupId, PermissionSetGroup.DeveloperName,
                   PermissionSetGroup.MasterLabel
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroupId != null
        ]) {
            userPSGIds.add(psa.PermissionSetGroupId);
            String lbl = (psa.PermissionSetGroup.MasterLabel != null)
                ? psa.PermissionSetGroup.MasterLabel
                : psa.PermissionSetGroup.DeveloperName;
            psgIdToLabel.put(psa.PermissionSetGroupId, lbl);
        }
        info.psgCount = userPSGIds.size();

        // 3) PSG members
        Map<Id, Set<Id>> psgToPSIds = new Map<Id, Set<Id>>();
        Map<Id, List<String>> psIdToPSGLabels = new Map<Id, List<String>>();
        Set<Id> psIdsFromPSGs = new Set<Id>();

        if (!userPSGIds.isEmpty()) {
            for (PermissionSetGroupComponent comp : [
                SELECT PermissionSetGroupId, PermissionSetId
                FROM PermissionSetGroupComponent
                WHERE PermissionSetGroupId IN :userPSGIds
            ]) {
                if (!psgToPSIds.containsKey(comp.PermissionSetGroupId)) {
                    psgToPSIds.put(comp.PermissionSetGroupId, new Set<Id>());
                }
                psgToPSIds.get(comp.PermissionSetGroupId).add(comp.PermissionSetId);
                psIdsFromPSGs.add(comp.PermissionSetId);

                if (!psIdToPSGLabels.containsKey(comp.PermissionSetId)) {
                    psIdToPSGLabels.put(comp.PermissionSetId, new List<String>());
                }
                String lbl = psgIdToLabel.get(comp.PermissionSetGroupId);
                if (lbl != null) psIdToPSGLabels.get(comp.PermissionSetId).add(lbl);
            }
        }

        // 4) PSG detail list
        for (Id psgId : userPSGIds) {
            Integer count = psgToPSIds.containsKey(psgId) ? psgToPSIds.get(psgId).size() : 0;
            info.psgDetails.add(psgIdToLabel.get(psgId) + ' (' + count + ' PS inside)');
        }
        info.psgList = String.join(info.psgDetails, '; ');

        // 5) Direct PS assignments
        Set<Id> directPSIds = new Set<Id>();
        Map<Id, String> directPSLabels = new Map<Id, String>();

        for (PermissionSetAssignment psa : [
            SELECT PermissionSetId, PermissionSet.Name, PermissionSet.Label
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId
              AND PermissionSetGroupId = null
              AND PermissionSet.IsOwnedByProfile = false
              AND PermissionSet.Type != 'Group'
            ORDER BY PermissionSet.Label
        ]) {
            directPSIds.add(psa.PermissionSetId);
            String lbl = (psa.PermissionSet.Label != null)
                ? psa.PermissionSet.Label : psa.PermissionSet.Name;
            directPSLabels.put(psa.PermissionSetId, lbl);
        }

        // 6) Classify Direct vs Via PSG
        Set<Id> allUniquePSIds = new Set<Id>();
        allUniquePSIds.addAll(directPSIds);
        allUniquePSIds.addAll(psIdsFromPSGs);

        Set<Id> needLabels = new Set<Id>(psIdsFromPSGs);
        needLabels.removeAll(directPSLabels.keySet());
        if (!needLabels.isEmpty()) {
            for (PermissionSet ps : [
                SELECT Id, Name, Label FROM PermissionSet WHERE Id IN :needLabels
            ]) {
                directPSLabels.put(ps.Id, (ps.Label != null) ? ps.Label : ps.Name);
            }
        }

        for (Id psId : allUniquePSIds) {
            info.allPSIdsForAccess.add(psId);
            String label = directPSLabels.get(psId);
            Boolean isDirect = directPSIds.contains(psId);
            Boolean isViaPSG = psIdsFromPSGs.contains(psId);

            if (isDirect && isViaPSG) {
                info.directCount++;
                info.psDetails.add(label + ' (Direct + Via PSG: '
                    + String.join(psIdToPSGLabels.get(psId), ', ') + ')');
            } else if (isViaPSG) {
                info.viaPSGCount++;
                info.psDetails.add(label + ' (Via PSG: '
                    + String.join(psIdToPSGLabels.get(psId), ', ') + ')');
            } else {
                info.directCount++;
                info.psDetails.add(label + ' (Direct)');
            }
        }

        info.psList = String.join(info.psDetails, '; ');
        return info;
    }

    // OBJECT ACCESS 

    private class ObjectAccessInfo {
        Integer totalObjects = 0;
        Integer modifyAllCount = 0;
        Integer viewAllCount = 0;
        Integer fullCrudCount = 0;
        String topObjectsText = '';
        List<String> objectRows = new List<String>();
        Map<String, Map<String, Boolean>> objectMatrix = new Map<String, Map<String, Boolean>>();
    }

    private static ObjectAccessInfo getObjectAccess(Set<Id> psIds) {
        ObjectAccessInfo info = new ObjectAccessInfo();
        if (psIds.isEmpty()) {
            info.topObjectsText = 'No object permissions found.';
            return info;
        }

        Map<String, Map<String, Boolean>> objMatrix = new Map<String, Map<String, Boolean>>();

        for (ObjectPermissions op : [
            SELECT SobjectType,
                PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete,
                PermissionsViewAllRecords, PermissionsModifyAllRecords
            FROM ObjectPermissions
            WHERE ParentId IN :psIds
        ]) {
            if (!objMatrix.containsKey(op.SobjectType)) {
                objMatrix.put(op.SobjectType, new Map<String, Boolean>{
                    'C' => false, 'R' => false, 'E' => false, 'D' => false,
                    'VA' => false, 'MA' => false
                });
            }
            Map<String, Boolean> p = objMatrix.get(op.SobjectType);
            if (op.PermissionsCreate)           p.put('C', true);
            if (op.PermissionsRead)             p.put('R', true);
            if (op.PermissionsEdit)             p.put('E', true);
            if (op.PermissionsDelete)           p.put('D', true);
            if (op.PermissionsViewAllRecords)   p.put('VA', true);
            if (op.PermissionsModifyAllRecords) p.put('MA', true);
        }

        info.totalObjects = objMatrix.size();
        info.objectMatrix = objMatrix;

        // Aggregate counts
        for (Map<String, Boolean> perms : objMatrix.values()) {
            if (perms.get('MA')) info.modifyAllCount++;
            if (perms.get('VA')) info.viewAllCount++;
            if (perms.get('C') && perms.get('R') && perms.get('E') && perms.get('D')) {
                info.fullCrudCount++;
            }
        }

        // Group for summary
        List<String> modifyAll = new List<String>();
        List<String> viewAll   = new List<String>();
        List<String> fullCrud  = new List<String>();
        List<String> readOnly  = new List<String>();
        List<String> partial   = new List<String>();

        List<String> sortedObjs = new List<String>(objMatrix.keySet());
        sortedObjs.sort();

        for (String objName : sortedObjs) {
            Map<String, Boolean> p = objMatrix.get(objName);
            if (p.get('MA')) {
                modifyAll.add(objName);
            } else if (p.get('VA')) {
                viewAll.add(objName);
            } else if (p.get('C') && p.get('R') && p.get('E') && p.get('D')) {
                fullCrud.add(objName);
            } else if (p.get('R') && !p.get('C') && !p.get('E') && !p.get('D')) {
                readOnly.add(objName);
            } else {
                partial.add(objName);
            }
        }

        // Clean plain-text summary (no emoji, no bold)
        String summary = '';
        if (!modifyAll.isEmpty())
            summary += 'Modify All (' + modifyAll.size() + '): '
                    + String.join(capList(modifyAll, 8), ', ') + '\n';
        if (!viewAll.isEmpty())
            summary += 'View All (' + viewAll.size() + '): '
                    + String.join(capList(viewAll, 8), ', ') + '\n';
        if (!fullCrud.isEmpty())
            summary += 'Full CRUD (' + fullCrud.size() + '): '
                    + String.join(capList(fullCrud, 8), ', ') + '\n';
        if (!readOnly.isEmpty())
            summary += 'Read Only (' + readOnly.size() + '): '
                    + String.join(capList(readOnly, 8), ', ') + '\n';
        if (!partial.isEmpty())
            summary += 'Partial (' + partial.size() + '): '
                    + String.join(capList(partial, 8), ', ');

        info.topObjectsText = (summary == '') ? 'No object permissions found.' : summary.trim();

        // CSV rows (no quotes on object name, no Source column)
        for (String objName : sortedObjs) {
            Map<String, Boolean> p = objMatrix.get(objName);
            info.objectRows.add(
                objName + ',' +
                p.get('C') + ',' + p.get('R') + ',' +
                p.get('E') + ',' + p.get('D') + ',' +
                p.get('VA') + ',' + p.get('MA')
            );
        }

        return info;
    }

    private static List<String> capList(List<String> items, Integer max) {
        if (items.size() <= max) return items;
        List<String> capped = new List<String>();
        for (Integer i = 0; i < max; i++) capped.add(items[i]);
        capped.add('+' + (items.size() - max) + ' more');
        return capped;
    }

    //  CSV GENERATION  

    private static String generateUserCSV(DeepDiveOutput output,
            PermissionSetInfo psInfo, ObjectAccessInfo objInfo) {

        String csv = '=== USER DEEP DIVE REPORT ===\n\n';

        csv += '=== BASIC INFO ===\n';
        csv += 'Field,Value\n';
        csv += 'Full Name,"' + safe(output.userFullName) + '"\n';
        csv += 'Username,"' + safe(output.username) + '"\n';
        csv += 'Email,"' + safe(output.email) + '"\n';
        csv += 'User ID,' + output.userId + '\n';
        csv += 'Profile,"' + safe(output.profileName) + '"\n';
        csv += 'Role,"' + safe(output.roleName) + '"\n';
        csv += 'User Type,"' + safe(output.userType) + '"\n';
        csv += 'Active,' + output.isActive + '\n';
        csv += 'Last Login,' + output.lastLogin + '\n';
        csv += 'Days Since Login,' + output.daysSinceLogin + '\n';
        csv += 'Created Date,' + output.createdDate + '\n';

        csv += '\n=== ACCESS SUMMARY ===\n';
        csv += 'Metric,Count\n';
        csv += 'Total Permission Sets,' + output.totalPermissionSets + '\n';
        csv += 'Direct Permission Sets,' + output.directPermissionSets + '\n';
        csv += 'Via PSG Permission Sets,' + output.viaPSGPermissionSets + '\n';
        csv += 'Permission Set Groups,' + output.totalPSGs + '\n';
        csv += 'Objects with Access,' + output.totalObjectsWithAccess + '\n';
        csv += 'Full CRUD Objects,' + output.fullCrudCount + '\n';
        csv += 'View All Objects,' + output.viewAllCount + '\n';
        csv += 'Modify All Objects,' + output.modifyAllCount + '\n';

        csv += '\n=== PERMISSION SETS ===\n';
        csv += 'Permission Set,Assigned Via\n';
        if (psInfo.psDetails.isEmpty()) {
            csv += 'None,N/A\n';
        } else {
            for (String detail : psInfo.psDetails) {
                Integer parenIdx = detail.lastIndexOf(' (');
                if (parenIdx > 0) {
                    String label = detail.substring(0, parenIdx);
                    String via = detail.substring(parenIdx + 2, detail.length() - 1);
                    csv += '"' + safe(label) + '","' + safe(via) + '"\n';
                } else {
                    csv += '"' + safe(detail) + '",""\n';
                }
            }
        }

        csv += '\n=== PERMISSION SET GROUPS ===\n';
        csv += 'PSG Name,# Permission Sets Inside\n';
        if (psInfo.psgDetails.isEmpty()) {
            csv += 'None,0\n';
        } else {
            for (String psg : psInfo.psgDetails) {
                Integer parenIdx = psg.lastIndexOf(' (');
                if (parenIdx > 0) {
                    String label = psg.substring(0, parenIdx);
                    String count = psg.substring(parenIdx + 2, psg.length() - 1);
                    csv += '"' + safe(label) + '","' + safe(count) + '"\n';
                } else {
                    csv += '"' + safe(psg) + '",""\n';
                }
            }
        }

        csv += '\n=== OBJECT ACCESS MATRIX ===\n';
        csv += 'Object,Create,Read,Edit,Delete,ViewAll,ModifyAll\n';
        for (String row : objInfo.objectRows) {
            csv += row + '\n';
        }

        return csv;
    }

    private static String safe(String val) {
        if (val == null) return '';
        return val.replace('"', '""');
    }

    //CONTENT VERSION  

    private static ContentVersion createFile(String csv, String username, Id targetUserId) {
        String cleanName = (username != null)
            ? username.replaceAll('[^a-zA-Z0-9]', '_') : 'user';
        String fileName = 'SSA_UserDeepDive_' + cleanName + '_'
                        + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';

        ContentVersion cv = new ContentVersion();
        cv.Title          = fileName;
        cv.PathOnClient   = fileName;
        cv.VersionData    = Blob.valueOf(csv);
        cv.Description    = 'SSA User Deep Dive Report for ' + username;
        cv.IsMajorVersion = true;
        insert cv;

        cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];

        shareFile(cv.ContentDocumentId, UserInfo.getUserId());
        if (targetUserId != null && targetUserId != UserInfo.getUserId()) {
            shareFile(cv.ContentDocumentId, targetUserId);
        }

        return cv;
    }

    private static void shareFile(Id docId, Id userId) {
        try {
            ContentDocumentLink cdl = new ContentDocumentLink();
            cdl.ContentDocumentId = docId;
            cdl.LinkedEntityId    = userId;
            cdl.ShareType         = 'V';
            cdl.Visibility        = 'AllUsers';
            insert cdl;
        } catch (Exception e) { }
    }
}