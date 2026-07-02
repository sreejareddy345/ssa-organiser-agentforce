public without sharing class SSA_PermissionSetHelper {
    
    public static Map<Id, Map<String, String>> getAllPermissionSetDetails() {
        Map<Id, Map<String, String>> result = new Map<Id, Map<String, String>>();
        
        Map<Id, String> profileNames = new Map<Id, String>();
        for (Profile pr : [SELECT Id, Name FROM Profile]) {
            profileNames.put(pr.Id, pr.Name);
        }
        
        for (PermissionSet ps : [
            SELECT Id, Name, Label, IsOwnedByProfile, Type, ProfileId, NamespacePrefix
            FROM PermissionSet
        ]) {
            String profName = 'N/A';
            if (ps.IsOwnedByProfile && ps.ProfileId != null && profileNames.containsKey(ps.ProfileId)) {
                profName = profileNames.get(ps.ProfileId);
            }
            
            result.put(ps.Id, new Map<String, String>{
                'Name' => ps.Name,
                'Label' => ps.Label,
                'IsOwnedByProfile' => String.valueOf(ps.IsOwnedByProfile),
                'Type' => ps.Type,
                'ProfileId' => ps.ProfileId,
                'ProfileName' => profName,
                'NamespacePrefix' => ps.NamespacePrefix
            });
        }
        
        return result;
    }
}