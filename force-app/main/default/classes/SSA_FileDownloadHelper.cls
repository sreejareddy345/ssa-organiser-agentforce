public with sharing class SSA_FileDownloadHelper {
    
    /**
     * Creates a ContentVersion file and returns a wrapper with 
     * file ID, direct download URL, and file name.
     */
    public static FileResult createDownloadableCSV(String fileName, String csvData, String description) {
        FileResult result = new FileResult();
        
        if (String.isBlank(csvData)) {
            result.success = false;
            result.message = 'No data to export.';
            return result;
        }
        
        try {
            ContentVersion cv = new ContentVersion();
            cv.Title = fileName;
            cv.PathOnClient = fileName + '.csv';
            cv.VersionData = Blob.valueOf(csvData);
            cv.Description = (description != null) ? description : 'SSA Export: ' + fileName;
            cv.IsMajorVersion = true;
            insert cv;
            
            ContentVersion inserted = [
                SELECT Id, ContentDocumentId, Title 
                FROM ContentVersion 
                WHERE Id = :cv.Id
            ];
            
            // Share with current user
            try {
                ContentDocumentLink cdl = new ContentDocumentLink();
                cdl.ContentDocumentId = inserted.ContentDocumentId;
                cdl.LinkedEntityId = UserInfo.getUserId();
                cdl.ShareType = 'V';
                cdl.Visibility = 'AllUsers';
                insert cdl;
            } catch (Exception e) {
                // Ignore if already linked
            }
            
            String downloadUrl = URL.getOrgDomainUrl().toExternalForm() 
                               + '/sfc/servlet.shepherd/document/download/' 
                               + inserted.ContentDocumentId;
            
            result.success = true;
            result.fileId = inserted.ContentDocumentId;
            result.fileName = fileName + '.csv';
            result.downloadUrl = downloadUrl;
            result.message = 'File created successfully.';
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'File creation failed: ' + e.getMessage();
        }
        
        return result;
    }
    
    public static FileResult createDownloadableCSV(String fileName, String csvData) {
        return createDownloadableCSV(fileName, csvData, null);
    }
    
    public class FileResult {
        public Boolean success = false;
        public String fileId;
        public String fileName;
        public String downloadUrl;
        public String message;
    }
}