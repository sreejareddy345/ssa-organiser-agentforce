public with sharing class SSA_AnalyzerController {

    // Get all picklist options for the UI
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getFilterOptions() {
        Map<String, Object> options = new Map<String, Object>();

        // All Objects
        List<Map<String, String>> objects = new List<Map<String, String>>();
        for (AggregateResult ar : [
            SELECT SobjectType FROM ObjectPermissions GROUP BY SobjectType ORDER BY SobjectType
        ]) {
            String name = (String) ar.get('SobjectType');
            objects.add(new Map<String, String>{ 'label' => name, 'value' => name });
        }
        options.put('objects', objects);

        // All Profiles
        List<Map<String, String>> profiles = new List<Map<String, String>>();
        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            profiles.add(new Map<String, String>{ 'label' => p.Name, 'value' => p.Name });
        }
        options.put('profiles', profiles);

        // All Permission Sets
        List<Map<String, String>> permSets = new List<Map<String, String>>();
        for (PermissionSet ps : [
            SELECT Id, Name, Label FROM PermissionSet
            WHERE IsOwnedByProfile = false AND Type != 'Group'
            ORDER BY Label
        ]) {
            String label = ps.Label != null ? ps.Label : ps.Name;
            permSets.add(new Map<String, String>{ 'label' => label, 'value' => ps.Name });
        }
        options.put('permissionSets', permSets);

        // All PSGs
        List<Map<String, String>> psgs = new List<Map<String, String>>();
        for (PermissionSetGroup psg : [
            SELECT Id, DeveloperName, MasterLabel FROM PermissionSetGroup ORDER BY MasterLabel
        ]) {
            String label = psg.MasterLabel != null ? psg.MasterLabel : psg.DeveloperName;
            psgs.add(new Map<String, String>{ 'label' => label, 'value' => psg.DeveloperName });
        }
        options.put('psgs', psgs);

        return options;
    }

    // Object Permission Analysis
    @AuraEnabled
    public static Map<String, Object> analyzeObjectPermissions(
        String objectName, String profileName, String permSetName, String crudFilter
    ) {
        Map<String, Object> result = new Map<String, Object>();

        String objFilter = String.isNotBlank(objectName) ? objectName : 'all';
        String nameFilter = 'all';
        String refFilter = 'all';

        if (String.isNotBlank(profileName) && profileName != 'all') {
            nameFilter = profileName;
            refFilter = 'Profile';
        } else if (String.isNotBlank(permSetName) && permSetName != 'all') {
            nameFilter = permSetName;
            refFilter = 'Permission Set';
        }

        String cFilter = String.isNotBlank(crudFilter) ? crudFilter : 'all';

        String query =
            'SELECT Id, SobjectType, ' +
            'PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete, ' +
            'PermissionsViewAllRecords, PermissionsModifyAllRecords, ' +
            'Parent.Name, Parent.Label, Parent.IsOwnedByProfile, Parent.ProfileId, Parent.Id ' +
            'FROM ObjectPermissions';

        if (objFilter != 'all') {
            query += ' WHERE SobjectType = \'' + String.escapeSingleQuotes(objFilter) + '\'';
        }
        query += ' ORDER BY SobjectType';

        List<ObjectPermissions> allOP = Database.query(query);

        Map<Id, String> profileNames = new Map<Id, String>();
        for (Profile pr : [SELECT Id, Name FROM Profile]) {
            profileNames.put(pr.Id, pr.Name);
        }

        Map<Id, String> permSetNames = new Map<Id, String>();
        for (PermissionSet ps : [SELECT Id, Name, Label, IsOwnedByProfile FROM PermissionSet WHERE IsOwnedByProfile = false]) {
            String displayName = ps.Label != null ? ps.Label : ps.Name;
            permSetNames.put(ps.Id, displayName);
        }

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Integer fullCrudCount = 0;
        Integer modifyAllCount = 0;
        Integer totalEntries = 0;

        for (ObjectPermissions op : allOP) {
            String refName;
            String refType;

            if (op.Parent.IsOwnedByProfile) {
                refType = 'Profile';
                refName = (op.Parent.ProfileId != null && profileNames.containsKey(op.Parent.ProfileId)) ?
                    profileNames.get(op.Parent.ProfileId) : (op.Parent.Name != null ? op.Parent.Name : 'Unknown');
            } else {
                refType = 'Permission Set';
                refName = (op.Parent.Id != null && permSetNames.containsKey(op.Parent.Id)) ?
                    permSetNames.get(op.Parent.Id) : (op.Parent.Label != null ? op.Parent.Label : op.Parent.Name);
            }

            if (refFilter != 'all' && !refType.equalsIgnoreCase(refFilter)) continue;
            if (nameFilter != 'all' && !refName.containsIgnoreCase(nameFilter)) continue;

            Boolean isFullCrud = op.PermissionsCreate && op.PermissionsRead && op.PermissionsEdit && op.PermissionsDelete;
            Boolean isModifyAll = op.PermissionsModifyAllRecords;

            if (cFilter == 'full_access' && !isFullCrud) continue;
            if (cFilter == 'modify_all' && !isModifyAll) continue;
            if (cFilter == 'delete' && !op.PermissionsDelete) continue;

            totalEntries++;
            if (isFullCrud) fullCrudCount++;
            if (isModifyAll) modifyAllCount++;

            rows.add(new Map<String, Object>{
                'objectName' => op.SobjectType,
                'refName' => refName,
                'refType' => refType,
                'canCreate' => op.PermissionsCreate,
                'canRead' => op.PermissionsRead,
                'canEdit' => op.PermissionsEdit,
                'canDelete' => op.PermissionsDelete,
                'viewAll' => op.PermissionsViewAllRecords,
                'modifyAll' => op.PermissionsModifyAllRecords
            });
        }

        result.put('rows', rows);
        result.put('totalEntries', totalEntries);
        result.put('fullCrudCount', fullCrudCount);
        result.put('modifyAllCount', modifyAllCount);

        return result;
    }

    // Profile Analysis
    @AuraEnabled
    public static Map<String, Object> analyzeProfiles(String profileName) {
        Map<String, Object> result = new Map<String, Object>();

        List<Map<String, Object>> rows = new List<Map<String, Object>>();

        List<AggregateResult> activeAgg = [
            SELECT ProfileId, COUNT(Id) cnt FROM User WHERE IsActive = true GROUP BY ProfileId
        ];
        List<AggregateResult> inactiveAgg = [
            SELECT ProfileId, COUNT(Id) cnt FROM User WHERE IsActive = false GROUP BY ProfileId
        ];

        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveMap = new Map<Id, Integer>();

        for (AggregateResult ar : activeAgg) { activeMap.put((Id) ar.get('ProfileId'), (Integer) ar.get('cnt')); }
        for (AggregateResult ar : inactiveAgg) { inactiveMap.put((Id) ar.get('ProfileId'), (Integer) ar.get('cnt')); }

        Integer totalUsed = 0;
        Integer totalUnused = 0;

        for (Profile p : [SELECT Id, Name FROM Profile ORDER BY Name]) {
            if (String.isNotBlank(profileName) && profileName != 'all' && !p.Name.containsIgnoreCase(profileName)) continue;

            Integer active = activeMap.containsKey(p.Id) ? activeMap.get(p.Id) : 0;
            Integer inactive = inactiveMap.containsKey(p.Id) ? inactiveMap.get(p.Id) : 0;
            Integer total = active + inactive;

            if (total > 0) totalUsed++; else totalUnused++;

            rows.add(new Map<String, Object>{
                'profileName' => p.Name,
                'profileId' => p.Id,
                'activeUsers' => active,
                'inactiveUsers' => inactive,
                'totalUsers' => total,
                'status' => total > 0 ? 'Used' : 'Unused'
            });
        }

        result.put('rows', rows);
        result.put('totalProfiles', rows.size());
        result.put('usedProfiles', totalUsed);
        result.put('unusedProfiles', totalUnused);

        return result;
    }

    // Permission Set Analysis
    @AuraEnabled
    public static Map<String, Object> analyzePermSets(String permSetName) {
        Map<String, Object> result = new Map<String, Object>();

        List<PermissionSet> allPS = [
            SELECT Id, Name, Label FROM PermissionSet
            WHERE IsOwnedByProfile = false AND Type != 'Group' ORDER BY Label
        ];

        List<AggregateResult> activeAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt FROM PermissionSetAssignment
            WHERE PermissionSet.IsOwnedByProfile = false AND PermissionSet.Type != 'Group' AND Assignee.IsActive = true
            GROUP BY PermissionSetId
        ];
        List<AggregateResult> inactiveAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt FROM PermissionSetAssignment
            WHERE PermissionSet.IsOwnedByProfile = false AND PermissionSet.Type != 'Group' AND Assignee.IsActive = false
            GROUP BY PermissionSetId
        ];

        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveMap = new Map<Id, Integer>();

        for (AggregateResult ar : activeAgg) { activeMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt')); }
        for (AggregateResult ar : inactiveAgg) { inactiveMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt')); }

        // PSG component mapping
        Map<Id, List<String>> psIdToPSGNames = new Map<Id, List<String>>();
        for (PermissionSetGroupComponent comp : [
            SELECT PermissionSetId, PermissionSetGroup.MasterLabel, PermissionSetGroup.DeveloperName
            FROM PermissionSetGroupComponent
        ]) {
            if (!psIdToPSGNames.containsKey(comp.PermissionSetId)) {
                psIdToPSGNames.put(comp.PermissionSetId, new List<String>());
            }
            String psgLabel = comp.PermissionSetGroup.MasterLabel != null ?
                comp.PermissionSetGroup.MasterLabel : comp.PermissionSetGroup.DeveloperName;
            psIdToPSGNames.get(comp.PermissionSetId).add(psgLabel);
        }

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Integer usedCount = 0;
        Integer unusedCount = 0;

        for (PermissionSet ps : allPS) {
            String label = ps.Label != null ? ps.Label : ps.Name;
            if (String.isNotBlank(permSetName) && permSetName != 'all' &&
                !label.containsIgnoreCase(permSetName) && !ps.Name.containsIgnoreCase(permSetName)) continue;

            Integer active = activeMap.containsKey(ps.Id) ? activeMap.get(ps.Id) : 0;
            Integer inactive = inactiveMap.containsKey(ps.Id) ? inactiveMap.get(ps.Id) : 0;
            Integer total = active + inactive;

            if (total > 0) usedCount++; else unusedCount++;

            List<String> psgNames = psIdToPSGNames.containsKey(ps.Id) ? psIdToPSGNames.get(ps.Id) : new List<String>();

            rows.add(new Map<String, Object>{
                'psName' => ps.Name,
                'psLabel' => label,
                'psId' => ps.Id,
                'activeUsers' => active,
                'inactiveUsers' => inactive,
                'totalUsers' => total,
                'status' => total > 0 ? 'Used' : 'Unused',
                'partOfPSGs' => String.join(psgNames, ', ')
            });
        }

        result.put('rows', rows);
        result.put('totalPS', rows.size());
        result.put('usedPS', usedCount);
        result.put('unusedPS', unusedCount);

        return result;
    }

    // PSG Analysis
    @AuraEnabled
    public static Map<String, Object> analyzePSGs(String psgName) {
        Map<String, Object> result = new Map<String, Object>();

        Map<Id, PermissionSetGroup> psgMap = new Map<Id, PermissionSetGroup>([
            SELECT Id, DeveloperName, MasterLabel, Status FROM PermissionSetGroup ORDER BY MasterLabel
        ]);

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
            SELECT PermissionSetGroupId, PermissionSet.Label, PermissionSet.Name FROM PermissionSetGroupComponent
        ]) {
            if (!psgComponents.containsKey(comp.PermissionSetGroupId)) {
                psgComponents.put(comp.PermissionSetGroupId, new List<String>());
            }
            String compLabel = comp.PermissionSet.Label != null ? comp.PermissionSet.Label : comp.PermissionSet.Name;
            psgComponents.get(comp.PermissionSetGroupId).add(compLabel);
        }

        List<AggregateResult> activeAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt FROM PermissionSetAssignment
            WHERE PermissionSetId IN :psgPSIds AND Assignee.IsActive = true GROUP BY PermissionSetId
        ];
        List<AggregateResult> inactiveAgg = [
            SELECT PermissionSetId, COUNT(AssigneeId) cnt FROM PermissionSetAssignment
            WHERE PermissionSetId IN :psgPSIds AND Assignee.IsActive = false GROUP BY PermissionSetId
        ];

        Map<Id, Integer> activeMap = new Map<Id, Integer>();
        Map<Id, Integer> inactiveMap = new Map<Id, Integer>();
        for (AggregateResult ar : activeAgg) { activeMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt')); }
        for (AggregateResult ar : inactiveAgg) { inactiveMap.put((Id) ar.get('PermissionSetId'), (Integer) ar.get('cnt')); }

        Map<Id, Id> companionToPSGId = new Map<Id, Id>();
        for (PermissionSet ps : psgPSMap.values()) {
            Id psgId = psNameToPSGId.containsKey(ps.Name) ? psNameToPSGId.get(ps.Name) :
                (ps.Label != null && psNameToPSGId.containsKey(ps.Label) ? psNameToPSGId.get(ps.Label) : null);
            if (psgId != null) companionToPSGId.put(ps.Id, psgId);
        }

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Set<Id> usedPSGIds = new Set<Id>();
        Integer usedCount = 0;
        Integer unusedCount = 0;

        for (Id companionId : psgPSMap.keySet()) {
            Id psgId = companionToPSGId.get(companionId);
            if (psgId == null) continue;
            PermissionSetGroup psg = psgMap.get(psgId);
            if (psg == null) continue;

            String label = psg.MasterLabel != null ? psg.MasterLabel : psg.DeveloperName;
            if (String.isNotBlank(psgName) && psgName != 'all' &&
                !label.containsIgnoreCase(psgName) && !psg.DeveloperName.containsIgnoreCase(psgName)) continue;

            Integer active = activeMap.containsKey(companionId) ? activeMap.get(companionId) : 0;
            Integer inactive = inactiveMap.containsKey(companionId) ? inactiveMap.get(companionId) : 0;
            Integer total = active + inactive;

            List<String> components = psgComponents.containsKey(psgId) ? psgComponents.get(psgId) : new List<String>();

            if (total > 0) { usedCount++; usedPSGIds.add(psgId); }

            rows.add(new Map<String, Object>{
                'psgName' => psg.DeveloperName,
                'psgLabel' => label,
                'psgId' => psg.Id,
                'status' => psg.Status,
                'activeUsers' => active,
                'inactiveUsers' => inactive,
                'totalUsers' => total,
                'numPS' => components.size(),
                'containedPS' => String.join(components, ', '),
                'usageStatus' => total > 0 ? 'Used' : 'Unused'
            });
        }

        // Add PSGs not found via companion
        for (PermissionSetGroup psg : psgMap.values()) {
            if (usedPSGIds.contains(psg.Id)) continue;
            Boolean alreadyAdded = false;
            for (Map<String, Object> row : rows) {
                if (row.get('psgId') == psg.Id) { alreadyAdded = true; break; }
            }
            if (alreadyAdded) continue;

            String label = psg.MasterLabel != null ? psg.MasterLabel : psg.DeveloperName;
            if (String.isNotBlank(psgName) && psgName != 'all' &&
                !label.containsIgnoreCase(psgName) && !psg.DeveloperName.containsIgnoreCase(psgName)) continue;

            List<String> components = psgComponents.containsKey(psg.Id) ? psgComponents.get(psg.Id) : new List<String>();
            unusedCount++;

            rows.add(new Map<String, Object>{
                'psgName' => psg.DeveloperName,
                'psgLabel' => label,
                'psgId' => psg.Id,
                'status' => psg.Status,
                'activeUsers' => 0,
                'inactiveUsers' => 0,
                'totalUsers' => 0,
                'numPS' => components.size(),
                'containedPS' => String.join(components, ', '),
                'usageStatus' => 'Unused'
            });
        }

        result.put('rows', rows);
        result.put('totalPSGs', rows.size());
        result.put('usedPSGs', usedCount);
        result.put('unusedPSGs', unusedCount);

        return result;
    }

    // User Analysis
    @AuraEnabled
    public static Map<String, Object> analyzeUsers(String profileName, String userName) {
        Map<String, Object> result = new Map<String, Object>();

        String query = 'SELECT Username, Name, Email, Profile.Name, ProfileId, IsActive, ' +
            'UserType, LastLoginDate, CreatedDate ' +
            'FROM User ORDER BY Username';

        List<User> users = Database.query(query);

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        Integer activeCount = 0;
        Integer inactiveCount = 0;

        for (User u : users) {
            String profName = u.Profile != null ? u.Profile.Name : '';

            if (String.isNotBlank(profileName) && profileName != 'all' && !profName.containsIgnoreCase(profileName)) continue;
            if (String.isNotBlank(userName) && userName != 'all' && !u.Name.containsIgnoreCase(userName) && !u.Username.containsIgnoreCase(userName)) continue;

            if (u.IsActive) activeCount++; else inactiveCount++;

            rows.add(new Map<String, Object>{
                'username' => u.Username,
                'fullName' => u.Name,
                'email' => u.Email,
                'profileName' => profName,
                'isActive' => u.IsActive,
                'userType' => u.UserType,
                'lastLogin' => u.LastLoginDate != null ? String.valueOf(u.LastLoginDate.date()) : 'NEVER',
                'createdDate' => String.valueOf(u.CreatedDate.date())
            });
        }

        result.put('rows', rows);
        result.put('totalUsers', rows.size());
        result.put('activeUsers', activeCount);
        result.put('inactiveUsers', inactiveCount);

        return result;
    }

    // Generate CSV for download
    @AuraEnabled
    public static String generateCSV(String analysisType, String jsonData, String fileName) {
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName + '.csv';
            cv.VersionData = Blob.valueOf(jsonData);
            cv.FirstPublishLocationId = UserInfo.getUserId();
            insert cv;

            ContentVersion inserted = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id];
            return inserted.ContentDocumentId;
        } catch (Exception e) {
            throw new AuraHandledException('File save failed: ' + e.getMessage());
        }
    }
}