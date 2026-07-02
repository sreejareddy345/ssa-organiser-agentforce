public with sharing class SSA_ExportReport {
    
    
    // REQUEST / RESPONSE WRAPPERS 

    
    public class ExportRequest {
        @InvocableVariable(label='Report Type' required=true
            description='object_permissions, user_permissions, or field_permissions')
        public String reportType;
        
        @InvocableVariable(label='Object Name' 
            description='Object API name or all')
        public String objectName;
        
        @InvocableVariable(label='Reference Type' 
            description='Profile, Permission Set, or all')
        public String referenceType;
        
        @InvocableVariable(label='Include Internal' 
            description='Include Salesforce internal permission sets. Default false.')
        public Boolean includeInternal;
    }
    
    public class ExportResponse {
        @InvocableVariable public String csvFileUrl;
        @InvocableVariable public String csvFileId;
        @InvocableVariable public String fileName;
        @InvocableVariable public String message;
        @InvocableVariable public Integer recordCount;
    }
    

    // INVOCABLE METHOD: EXPORT CSV  
    
    @InvocableMethod(
        label='Export SSA Report to CSV'
        description='Generates a downloadable CSV file with permission analysis data. Returns a direct download URL.'
        category='SSA Org Analyzer'
    )
    public static List<ExportResponse> exportCSV(List<ExportRequest> requests) {
        List<ExportResponse> responses = new List<ExportResponse>();
        
        // Load permission set data once
        Map<Id, Map<String, String>> allPSData = SSA_PermissionSetHelper.getAllPermissionSetDetails();
        
        for (ExportRequest req : requests) {
            ExportResponse res = new ExportResponse();
            
            try {
                String reportType = (req.reportType != null) 
                    ? req.reportType.trim().toLowerCase() 
                    : 'object_permissions';
                String objFilter = (req.objectName != null) 
                    ? req.objectName.trim() 
                    : 'all';
                String refFilter = (req.referenceType != null) 
                    ? req.referenceType.trim() 
                    : 'all';
                Boolean includeInternal = (req.includeInternal != null) 
                    ? req.includeInternal 
                    : false;
                
                // Build the CSV based on report type
                String csv = '';
                Integer rowCount = 0;
                
                if (reportType == 'object_permissions') {
                    Map<String, Object> r = buildObjectPermCSV(objFilter, refFilter, includeInternal, allPSData);
                    csv = (String) r.get('csv');
                    rowCount = (Integer) r.get('rows');
                } else if (reportType == 'user_permissions') {
                    Map<String, Object> r = buildUserPermCSV(objFilter, refFilter, includeInternal, allPSData);
                    csv = (String) r.get('csv');
                    rowCount = (Integer) r.get('rows');
                } else if (reportType == 'field_permissions') {
                    Map<String, Object> r = buildFieldPermCSV(objFilter, refFilter, includeInternal, allPSData);
                    csv = (String) r.get('csv');
                    rowCount = (Integer) r.get('rows');
                } else {
                    res.message = ' Invalid reportType: ' + reportType;
                    res.recordCount = 0;
                    responses.add(res);
                    continue;
                }
                
                // No data case  
                if (rowCount == 0 || String.isBlank(csv)) {
                    res.message = 'No data found — no file generated.';
                    res.recordCount = 0;
                    responses.add(res);
                    continue;
                }
                
                // Generate the file  
                ContentVersion cv = generateCSVFile(csv, reportType, objFilter, refFilter);
                
                // Set outputs  
                res.csvFileId = cv.ContentDocumentId;
                res.fileName = cv.Title;
                res.recordCount = rowCount;
                res.csvFileUrl = URL.getOrgDomainUrl().toExternalForm() 
                               + '/sfc/servlet.shepherd/document/download/' 
                               + cv.ContentDocumentId;
                res.message = ' CSV file generated successfully with ' + rowCount + ' rows.';
                
            } catch (Exception e) {
                res.message = ' Error: ' + e.getMessage();
                res.recordCount = 0;
            }
            
            responses.add(res);
        }
        return responses;
    }
    
    // HELPER: GENERATE CSV FILE 

    
    private static ContentVersion generateCSVFile(
        String csv, 
        String reportType, 
        String objFilter, 
        String refFilter
    ) {
        // Create file in Salesforce Files
        String fileName = 'SSA_' + reportType + '_' + objFilter + '_' 
                        + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';
        
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf(csv);
        cv.Description = 'SSA ' + reportType + ' Export | object=' + objFilter 
                       + ', ref=' + refFilter;
        cv.IsMajorVersion = true;
        insert cv;
        
        cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];
        
        // Share with current user (same as SODExporter)
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
    

    // HELPER: CSV FIELD ESCAPE 
    
    private static String csvEscape(String val) {
        if (val == null) return '';
        if (val.contains(',') || val.contains('"') || val.contains('\n')) {
            return '"' + val.replace('"', '""') + '"';
        }
        return val;
    }
    
    private static String safe(String val) {
        if (val == null || val == '') return 'N/A';
        return val.replace('"', '""');
    }
    
   
    // PS DATA HELPERS
   
    
    private static String getPSField(Id pid, String field, Map<Id, Map<String, String>> allPSData) {
        if (allPSData.containsKey(pid)) {
            String val = allPSData.get(pid).get(field);
            return safe(val);
        }
        if (field == 'Name' || field == 'Label') return String.valueOf(pid);
        if (field == 'ProfileName') return 'N/A';
        if (field == 'IsOwnedByProfile') return 'false';
        return 'N/A';
    }
    
    private static Boolean isOwned(Id pid, Map<Id, Map<String, String>> allPSData) {
        if (allPSData.containsKey(pid)) {
            return allPSData.get(pid).get('IsOwnedByProfile') == 'true';
        }
        return false;
    }
    
    private static Boolean isInternal(Id pid, Map<Id, Map<String, String>> allPSData) {
        if (!allPSData.containsKey(pid)) return true;
        Map<String, String> data = allPSData.get(pid);
        if (data.get('IsOwnedByProfile') == 'true') return false;
        String psType = data.get('Type');
        String ns = data.get('NamespacePrefix');
        if (psType == 'Session' || psType == 'Standard') return true;
        if (ns != null && ns != '') return true;
        return false;
    }
    
    private static Boolean shouldSkip(Id pid, Boolean includeInternal, Map<Id, Map<String, String>> allPSData) {
        if (includeInternal) return false;
        return isInternal(pid, allPSData);
    }
    
    private static String getAccessLevel(ObjectPermissions op) {
        Boolean isFullCrud = op.PermissionsCreate && op.PermissionsRead && op.PermissionsEdit && op.PermissionsDelete;
        Boolean isModifyAll = op.PermissionsModifyAllRecords;
        Boolean isViewAll = op.PermissionsViewAllRecords;
        Boolean isReadOnly = op.PermissionsRead && !op.PermissionsCreate && !op.PermissionsEdit && !op.PermissionsDelete;
        
        if (isModifyAll) return 'FULL+MODIFY ALL';
        if (isFullCrud && isViewAll) return 'FULL CRED+VIEW ALL';
        if (isFullCrud) return 'FULL CRED';
        if (isReadOnly) return 'READ ONLY';
        if (op.PermissionsRead && op.PermissionsEdit && !op.PermissionsDelete) return 'READ+EDIT';
        if (op.PermissionsRead && op.PermissionsCreate && !op.PermissionsDelete) return 'READ+CREATE';
        return 'CUSTOM';
    }
    

    // Object Permissions CSV Builder
    
    
    private static Map<String, Object> buildObjectPermCSV(
        String objFilter, String refFilter,
        Boolean includeInternal, Map<Id, Map<String, String>> allPSData
    ) {
        String query =
            'SELECT Id, SobjectType, ' +
            'PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete, ' +
            'PermissionsViewAllRecords, PermissionsModifyAllRecords, ' +
            'ParentId FROM ObjectPermissions';
        
        if (objFilter != 'all') {
            query += ' WHERE SobjectType = \'' + String.escapeSingleQuotes(objFilter) + '\'';
        }
        query += ' ORDER BY SobjectType';
        
        List<ObjectPermissions> allOP = Database.query(query);
        
        String csv = 'Object,PermissionSet.IsOwnedByProfile,PermissionSet.Name,PermissionSet.Label,' +
            'Profile.Name,PermissionSet.Id,' +
            'PermissionsCreate,PermissionsRead,PermissionsEdit,PermissionsDelete,' +
            'PermissionsViewAllRecords,PermissionsModifyAllRecords,AccessLevel\n';
        Integer rows = 0;
        
        for (ObjectPermissions op : allOP) {
            Id pid = op.ParentId;
            
            if (shouldSkip(pid, includeInternal, allPSData)) continue;
            
            Boolean owned = isOwned(pid, allPSData);
            
            if (refFilter != 'all') {
                if (refFilter.equalsIgnoreCase('Profile') && !owned) continue;
                if (refFilter.equalsIgnoreCase('Permission Set') && owned) continue;
            }
            
            String psName = getPSField(pid, 'Name', allPSData);
            String psLabel = getPSField(pid, 'Label', allPSData);
            String profName = getPSField(pid, 'ProfileName', allPSData);
            String accessLevel = getAccessLevel(op);
            
            if (csv.length() < 5000000) {
                csv += '"' + op.SobjectType + '",' +
                    owned + ',"' +
                    safe(psName) + '","' +
                    safe(psLabel) + '","' +
                    safe(profName) + '",' +
                    pid + ',' +
                    op.PermissionsCreate + ',' +
                    op.PermissionsRead + ',' +
                    op.PermissionsEdit + ',' +
                    op.PermissionsDelete + ',' +
                    op.PermissionsViewAllRecords + ',' +
                    op.PermissionsModifyAllRecords + ',"' +
                    accessLevel + '"\n';
            }
            rows++;
        }
        
        return new Map<String, Object>{ 'csv' => csv, 'rows' => rows };
    }
    
    
    // User Permissions CSV Builder

    
    private static Map<String, Object> buildUserPermCSV(
        String objFilter, String refFilter,
        Boolean includeInternal, Map<Id, Map<String, String>> allPSData
    ) {
        List<PermissionSetAssignment> allPSA = [
            SELECT AssigneeId, PermissionSetId,
                Assignee.Name, Assignee.Username, Assignee.Email,
                Assignee.IsActive, Assignee.Profile.Name, Assignee.UserRole.Name
            FROM PermissionSetAssignment
            WHERE Assignee.IsActive = true
            ORDER BY Assignee.Name
        ];
        
        Set<Id> psIds = new Set<Id>();
        for (PermissionSetAssignment psa : allPSA) {
            Id psId = psa.PermissionSetId;
            if (!shouldSkip(psId, includeInternal, allPSData)) {
                psIds.add(psId);
            }
        }
        
        String opQuery =
            'SELECT ParentId, SobjectType, ' +
            'PermissionsCreate, PermissionsRead, PermissionsEdit, PermissionsDelete, ' +
            'PermissionsViewAllRecords, PermissionsModifyAllRecords ' +
            'FROM ObjectPermissions WHERE ParentId IN :psIds';
        
        if (objFilter != 'all') {
            opQuery += ' AND SobjectType = \'' + String.escapeSingleQuotes(objFilter) + '\'';
        }
        
        List<ObjectPermissions> allOP = Database.query(opQuery);
        
        Map<Id, Map<String, ObjectPermissions>> psObjPerms = new Map<Id, Map<String, ObjectPermissions>>();
        for (ObjectPermissions op : allOP) {
            if (!psObjPerms.containsKey(op.ParentId)) {
                psObjPerms.put(op.ParentId, new Map<String, ObjectPermissions>());
            }
            psObjPerms.get(op.ParentId).put(op.SobjectType, op);
        }
        
        String csv = 'Assignee.Name,Assignee.UserName,Assignee.Email,' +
            'Assignee.Profile.Name,Assignee.UserRole,' +
            'PermissionSet.IsOwnedByProfile,PermissionSet.Name,PermissionSet.Label,' +
            'Profile.Name,IsActive,PermissionSet.Id,' +
            'Permission OBJECT,' +
            'PermissionsCreate,PermissionsRead,PermissionsEdit,PermissionsDelete,' +
            'PermissionsViewAllRecords,PermissionsModifyAllRecords\n';
        Integer rows = 0;
        
        for (PermissionSetAssignment psa : allPSA) {
            Id psId = psa.PermissionSetId;
            
            if (shouldSkip(psId, includeInternal, allPSData)) continue;
            
            Boolean owned = isOwned(psId, allPSData);
            
            if (refFilter != 'all') {
                if (refFilter.equalsIgnoreCase('Profile') && !owned) continue;
                if (refFilter.equalsIgnoreCase('Permission Set') && owned) continue;
            }
            
            if (!psObjPerms.containsKey(psId)) continue;
            
            Map<String, ObjectPermissions> objPerms = psObjPerms.get(psId);
            
            String assigneeName = psa.Assignee.Name != null ? psa.Assignee.Name.replace('"', '""') : '';
            String assigneeUsername = psa.Assignee.Username != null ? psa.Assignee.Username : '';
            String assigneeEmail = psa.Assignee.Email != null ? psa.Assignee.Email : '';
            String assigneeProfile = psa.Assignee.Profile != null ? psa.Assignee.Profile.Name : 'N/A';
            String assigneeRole = psa.Assignee.UserRole != null ? psa.Assignee.UserRole.Name : 'N/A';
            Boolean isActive = psa.Assignee.IsActive;
            
            String psName = getPSField(psId, 'Name', allPSData);
            String psLabel = getPSField(psId, 'Label', allPSData);
            String profName = getPSField(psId, 'ProfileName', allPSData);
            
            for (String objName : objPerms.keySet()) {
                ObjectPermissions op = objPerms.get(objName);
                
                if (csv.length() < 5000000) {
                    csv += '"' + assigneeName + '","' +
                        assigneeUsername + '","' +
                        assigneeEmail + '","' +
                        assigneeProfile + '","' +
                        assigneeRole + '",' +
                        owned + ',"' +
                        safe(psName) + '","' +
                        safe(psLabel) + '","' +
                        safe(profName) + '",' +
                        isActive + ',' +
                        psId + ',"' +
                        objName + '",' +
                        op.PermissionsCreate + ',' +
                        op.PermissionsRead + ',' +
                        op.PermissionsEdit + ',' +
                        op.PermissionsDelete + ',' +
                        op.PermissionsViewAllRecords + ',' +
                        op.PermissionsModifyAllRecords + '\n';
                }
                rows++;
            }
        }
        
        return new Map<String, Object>{ 'csv' => csv, 'rows' => rows };
    }
    
   
    // Field Permissions CSV Builder
  
    
    private static Map<String, Object> buildFieldPermCSV(
        String objFilter, String refFilter,
        Boolean includeInternal, Map<Id, Map<String, String>> allPSData
    ) {
        String query =
            'SELECT SobjectType, Field, PermissionsRead, PermissionsEdit, ParentId ' +
            'FROM FieldPermissions';
        
        if (objFilter != 'all') {
            query += ' WHERE SobjectType = \'' + String.escapeSingleQuotes(objFilter) + '\'';
        }
        query += ' ORDER BY SobjectType, Field';
        
        List<FieldPermissions> allFP = Database.query(query);
        
        String csv = 'Object,Field,PermissionSet.IsOwnedByProfile,PermissionSet.Name,PermissionSet.Label,' +
            'Profile.Name,PermissionSet.Id,PermissionsRead,PermissionsEdit\n';
        Integer rows = 0;
        
        for (FieldPermissions fp : allFP) {
            Id pid = fp.ParentId;
            
            if (shouldSkip(pid, includeInternal, allPSData)) continue;
            
            Boolean owned = isOwned(pid, allPSData);
            
            if (refFilter != 'all') {
                if (refFilter.equalsIgnoreCase('Profile') && !owned) continue;
                if (refFilter.equalsIgnoreCase('Permission Set') && owned) continue;
            }
            
            String fieldName = fp.Field != null && fp.Field.contains('.') 
                ? fp.Field.substringAfter('.') : fp.Field;
            
            String psName = getPSField(pid, 'Name', allPSData);
            String psLabel = getPSField(pid, 'Label', allPSData);
            String profName = getPSField(pid, 'ProfileName', allPSData);
            
            if (csv.length() < 5000000) {
                csv += '"' + fp.SobjectType + '","' +
                    fieldName + '",' +
                    owned + ',"' +
                    safe(psName) + '","' +
                    safe(psLabel) + '","' +
                    safe(profName) + '",' +
                    pid + ',' +
                    fp.PermissionsRead + ',' +
                    fp.PermissionsEdit + '\n';
            }
            rows++;
        }
        
        return new Map<String, Object>{ 'csv' => csv, 'rows' => rows };
    }
}