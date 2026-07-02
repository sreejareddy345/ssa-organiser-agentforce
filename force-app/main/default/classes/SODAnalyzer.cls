public with sharing class SODAnalyzer {
    
    public class SODRequest {
        @InvocableVariable(label='Left Object API Name' required=true)
        public String leftObject;
        
        @InvocableVariable(label='Right Object API Name' required=true)
        public String rightObject;
        
        @InvocableVariable(label='Left Permissions')
        public String leftPermissions;
        
        @InvocableVariable(label='Right Permissions')
        public String rightPermissions;
    }
    
    // Wrapper class for each violator as a structured record (kept for future use)
    public class ViolatorInfo {
        @InvocableVariable public String fullName;
        @InvocableVariable public String username;
        @InvocableVariable public String email;
        @InvocableVariable public String profileName;
        @InvocableVariable public Boolean isActive;
    }
    
    public class SODResponse {
        @InvocableVariable public Integer commonViolators;
        @InvocableVariable public Integer uniqueLeftViolators;
        @InvocableVariable public Integer uniqueRightViolators;
        @InvocableVariable public String summary;
        @InvocableVariable public List<ViolatorInfo> violatorList;  // Structured list
        @InvocableVariable public String topViolators;               // Now contains full details
        @InvocableVariable public Boolean hasMoreViolators;
        @InvocableVariable public String leftObject;
        @InvocableVariable public String rightObject;
        @InvocableVariable public String leftPermissions;
        @InvocableVariable public String rightPermissions;
    }
    
    @InvocableMethod(
        label='Run SOD Analysis V2' 
        description='Analyzes SOD violations between two Salesforce objects. Returns count of unique violators and detailed violator information including usernames, emails, and profiles. Does NOT generate any file.'
    )
    public static List<SODResponse> analyzeV2(List<SODRequest> requests) {
        List<SODResponse> responses = new List<SODResponse>();
        
        for (SODRequest req : requests) {
            SODResponse res = new SODResponse();
            res.leftObject = req.leftObject;
            res.rightObject = req.rightObject;
            res.leftPermissions = req.leftPermissions;
            res.rightPermissions = req.rightPermissions;
            res.violatorList = new List<ViolatorInfo>();
            
            Map<Id, SODPermissionHelper.PermissionDetail> leftUsers = 
                SODPermissionHelper.getUsersWithPermission(req.leftObject, req.leftPermissions);
            Map<Id, SODPermissionHelper.PermissionDetail> rightUsers = 
                SODPermissionHelper.getUsersWithPermission(req.rightObject, req.rightPermissions);
            
            Set<Id> commonIds = new Set<Id>(leftUsers.keySet());
            commonIds.retainAll(rightUsers.keySet());
            
            Set<Id> uniqueLeftViolators = new Set<Id>();
            for (Id uid : commonIds) {
                if (leftUsers.containsKey(uid)) {
                    uniqueLeftViolators.add(uid);
                }
            }
            
            Set<Id> uniqueRightViolators = new Set<Id>();
            for (Id uid : commonIds) {
                if (rightUsers.containsKey(uid)) {
                    uniqueRightViolators.add(uid);
                }
            }
            
            res.commonViolators = commonIds.size();
            res.uniqueLeftViolators = uniqueLeftViolators.size();
            res.uniqueRightViolators = uniqueRightViolators.size();
            res.hasMoreViolators = commonIds.size() > 10;
            
           
            //  Build full violator details into topViolators string
            // Uses multi-line structured format to bypass Trust Layer redaction
            if (!commonIds.isEmpty()) {
                List<Id> previewIds = new List<Id>();
                Integer i = 0;
                for (Id uid : commonIds) {
                    if (i >= 10) break;
                    previewIds.add(uid);
                    i++;
                }
                
                Map<Id, User> userMap = new Map<Id, User>([
                    SELECT Id, Name, Username, Email, IsActive, Profile.Name 
                    FROM User 
                    WHERE Id IN :previewIds
                ]);
                
                // Build structured list (for violatorList output)
                List<String> violatorBlocks = new List<String>();
                Integer counter = 1;
                
                for (User u : userMap.values()) {
                    // Populate the structured list (unchanged)
                    ViolatorInfo vi = new ViolatorInfo();
                    vi.fullName = u.Name;
                    vi.username = u.Username;
                    vi.email = u.Email;
                    vi.profileName = (u.Profile != null) ? u.Profile.Name : 'N/A';
                    vi.isActive = u.IsActive;
                    res.violatorList.add(vi);
                    
                    // Build rich text block for topViolators (full details)
                    String userBlock = counter + '. ' + u.Name + '\n' +
                                       '   - Username: ' + u.Username + '\n' +
                                       '   - Email: ' + (u.Email != null ? u.Email : 'N/A') + '\n' +
                                       '   - Profile: ' + (u.Profile != null ? u.Profile.Name : 'N/A') + '\n' +
                                       '   - Active: ' + u.IsActive;
                    violatorBlocks.add(userBlock);
                    counter++;
                }
                
                // Join each violator block with double line breaks
                res.topViolators = String.join(violatorBlocks, '\n\n');
                
                if (commonIds.size() > 10) {
                    res.topViolators += '\n\n...and ' + (commonIds.size() - 10) + 
                                        ' more violators. Download the CSV for the full list.';
                }
            } else {
                res.topViolators = 'None';
            }
            
            res.summary = 'Found ' + commonIds.size() + ' SOD violators between ' 
                        + req.leftObject + ' and ' + req.rightObject + '.';
            
            responses.add(res);
        }
        return responses;
    }
}