public with sharing class SODPermissionHelper {
    

    // PERMISSION DETAIL WRAPPER

    
    public class PermissionDetail {
        public Boolean hasCreate = false;
        public Boolean hasEdit = false;
        public Boolean hasDelete = false;
        public Boolean hasModifyAll = false;
        public Set<String> sourceProfiles = new Set<String>();
        public Set<String> sourcePermSets = new Set<String>();
    }
    
    
    // GET USERS WITH PERMISSION ON OBJECT

    
    public static Map<Id, PermissionDetail> getUsersWithPermission(String objectName, String perms) {
        Set<String> permFields = parsePerms(perms);
        
        List<String> conditions = new List<String>();
        if (permFields.contains('CREATE'))    conditions.add('PermissionsCreate = true');
        if (permFields.contains('EDIT'))      conditions.add('PermissionsEdit = true');
        if (permFields.contains('DELETE'))    conditions.add('PermissionsDelete = true');
        if (permFields.contains('MODIFYALL')) conditions.add('PermissionsModifyAllRecords = true');
        
        if (conditions.isEmpty()) return new Map<Id, PermissionDetail>();
        
        String permFilter = '(' + String.join(conditions, ' OR ') + ')';
        String objName = String.escapeSingleQuotes(objectName);
        
        String query = 'SELECT ParentId, Parent.Name, Parent.IsOwnedByProfile, Parent.Profile.Name, ' +
                       'PermissionsCreate, PermissionsEdit, PermissionsDelete, PermissionsModifyAllRecords ' +
                       'FROM ObjectPermissions ' +
                       'WHERE SobjectType = \'' + objName + '\' AND ' + permFilter;
        
        List<ObjectPermissions> opList = Database.query(query);
        
        Map<Id, ObjectPermissions> permSetToOP = new Map<Id, ObjectPermissions>();
        for (ObjectPermissions op : opList) {
            permSetToOP.put(op.ParentId, op);
        }
        
        if (permSetToOP.isEmpty()) return new Map<Id, PermissionDetail>();
        
        Map<Id, PermissionDetail> userPermMap = new Map<Id, PermissionDetail>();
        
        for (PermissionSetAssignment psa : [
            SELECT AssigneeId, PermissionSetId, PermissionSet.Name, 
                   PermissionSet.IsOwnedByProfile, PermissionSet.Profile.Name
            FROM PermissionSetAssignment
            WHERE PermissionSetId IN :permSetToOP.keySet()
              AND Assignee.IsActive = true
              AND Assignee.UserType = 'Standard'
        ]) {
            PermissionDetail pd = userPermMap.get(psa.AssigneeId);
            if (pd == null) {
                pd = new PermissionDetail();
                userPermMap.put(psa.AssigneeId, pd);
            }
            
            ObjectPermissions op = permSetToOP.get(psa.PermissionSetId);
            if (op.PermissionsCreate)            pd.hasCreate = true;
            if (op.PermissionsEdit)              pd.hasEdit = true;
            if (op.PermissionsDelete)            pd.hasDelete = true;
            if (op.PermissionsModifyAllRecords)  pd.hasModifyAll = true;
            
            if (psa.PermissionSet.IsOwnedByProfile) {
                pd.sourceProfiles.add(psa.PermissionSet.Profile.Name);
            } else {
                pd.sourcePermSets.add(psa.PermissionSet.Name);
            }
        }
        return userPermMap;
    }
    

    // PARSE PERMISSION STRING
   
    
    public static Set<String> parsePerms(String perms) {
        Set<String> result = new Set<String>();
        if (String.isBlank(perms)) {
            result.addAll(new List<String>{'CREATE','EDIT','DELETE','MODIFYALL'});
            return result;
        }
        for (String p : perms.split(',')) {
            result.add(p.trim().toUpperCase());
        }
        return result;
    }
}