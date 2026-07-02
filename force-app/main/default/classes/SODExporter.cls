public with sharing class SODExporter {
    

    // REQUEST / RESPONSE WRAPPERS

    
    public class ExportRequest {
        @InvocableVariable(label='Left Object API Name' required=true)
        public String leftObject;
        
        @InvocableVariable(label='Right Object API Name' required=true)
        public String rightObject;
        
        @InvocableVariable(label='Left Permissions')
        public String leftPermissions;
        
        @InvocableVariable(label='Right Permissions')
        public String rightPermissions;
    }
    
    public class ExportResponse {
        @InvocableVariable public String csvFileUrl;
        @InvocableVariable public String csvFileId;
        @InvocableVariable public String fileName;
        @InvocableVariable public String message;
        @InvocableVariable public Integer recordCount;
    }
    

    // INVOCABLE METHOD: EXPORT CSV — ONLY WHEN USER CONFIRMS

    
    @InvocableMethod(
        label='Export SOD Report to CSV' 
        description='Generates a downloadable CSV file with full SOD violation details. ONLY call this when the user explicitly confirms with "yes", "download", "export", or similar. Never call automatically.'
    )
    public static List<ExportResponse> exportCSV(List<ExportRequest> requests) {
        List<ExportResponse> responses = new List<ExportResponse>();
        
        for (ExportRequest req : requests) {
            ExportResponse res = new ExportResponse();
            
            Map<Id, SODPermissionHelper.PermissionDetail> leftUsers = 
                SODPermissionHelper.getUsersWithPermission(req.leftObject, req.leftPermissions);
            Map<Id, SODPermissionHelper.PermissionDetail> rightUsers = 
                SODPermissionHelper.getUsersWithPermission(req.rightObject, req.rightPermissions);
            
            Set<Id> commonIds = new Set<Id>(leftUsers.keySet());
            commonIds.retainAll(rightUsers.keySet());
            
            if (commonIds.isEmpty()) {
                res.message = 'No violations found — no file generated.';
                res.recordCount = 0;
                responses.add(res);
                continue;
            }
            
            Map<Id, User> userMap = new Map<Id, User>([
                SELECT Id, Username, Name, IsActive, Profile.Name 
                FROM User 
                WHERE Id IN :commonIds
            ]);
            
            ContentVersion cv = generateCSVFile(
                commonIds, leftUsers, rightUsers, userMap,
                req.leftObject, req.rightObject
            );
            
            res.csvFileId = cv.ContentDocumentId;
            res.fileName = cv.Title;
            res.recordCount = commonIds.size();
            res.csvFileUrl = URL.getOrgDomainUrl().toExternalForm() 
                           + '/sfc/servlet.shepherd/document/download/' 
                           + cv.ContentDocumentId;
            res.message = ' CSV file generated successfully with ' + commonIds.size() + ' violators.';
            
            responses.add(res);
        }
        return responses;
    }
    
 
    // HELPER: GENERATE CSV FILE
  
    
    private static ContentVersion generateCSVFile(
        Set<Id> commonIds,
        Map<Id, SODPermissionHelper.PermissionDetail> leftUsers,
        Map<Id, SODPermissionHelper.PermissionDetail> rightUsers,
        Map<Id, User> userMap,
        String leftObj,
        String rightObj
    ) {
        String csv = '';
        
        // Header
        csv += 'Username,Full Name,Is Active,Profile,' +
               leftObj + '_Create,' + leftObj + '_Edit,' + leftObj + '_Delete,' + leftObj + '_ModifyAll,' +
               rightObj + '_Create,' + rightObj + '_Edit,' + rightObj + '_Delete,' + rightObj + '_ModifyAll,' +
               leftObj + '_Source_Profiles,' + leftObj + '_Source_PermSets,' +
               rightObj + '_Source_Profiles,' + rightObj + '_Source_PermSets,' +
               'SOD_Violation\n';
        
        // Rows
        for (Id uid : commonIds) {
            User u = userMap.get(uid);
            if (u == null) continue;
            
            SODPermissionHelper.PermissionDetail lp = leftUsers.get(uid);
            SODPermissionHelper.PermissionDetail rp = rightUsers.get(uid);
            
            csv += csvEscape(u.Username) + ',';
            csv += csvEscape(u.Name) + ',';
            csv += u.IsActive + ',';
            csv += csvEscape(u.Profile != null ? u.Profile.Name : '') + ',';
            
            csv += lp.hasCreate + ',' + lp.hasEdit + ',' + lp.hasDelete + ',' + lp.hasModifyAll + ',';
            csv += rp.hasCreate + ',' + rp.hasEdit + ',' + rp.hasDelete + ',' + rp.hasModifyAll + ',';
            
            csv += csvEscape(String.join(new List<String>(lp.sourceProfiles), '; ')) + ',';
            csv += csvEscape(String.join(new List<String>(lp.sourcePermSets), '; ')) + ',';
            csv += csvEscape(String.join(new List<String>(rp.sourceProfiles), '; ')) + ',';
            csv += csvEscape(String.join(new List<String>(rp.sourcePermSets), '; ')) + ',';
            csv += 'Yes\n';
        }
        
        // Create file in Salesforce Files
        String fileName = 'SOD_Violations_' + leftObj + '_vs_' + rightObj + '_' 
                        + Datetime.now().format('yyyyMMdd_HHmmss') + '.csv';
        
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf(csv);
        cv.Description = 'SOD Violation Report: ' + leftObj + ' vs ' + rightObj;
        cv.IsMajorVersion = true;
        insert cv;
        
        cv = [SELECT Id, ContentDocumentId, Title FROM ContentVersion WHERE Id = :cv.Id];
        
        // Share with current user
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
}