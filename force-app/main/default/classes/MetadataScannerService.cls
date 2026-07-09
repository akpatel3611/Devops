public with sharing class MetadataScannerService {

    // ==========================================
    // DTO INNER CLASSES
    // ==========================================
    
    public class ChangedFile {
        @AuraEnabled public String filename {get;set;}
        @AuraEnabled public String status {get;set;} // e.g. added, modified, deleted, removed, renamed
        @AuraEnabled public String previousFilename {get;set;}
        @AuraEnabled public String sha {get;set;}
        @AuraEnabled public String blobUrl {get;set;}
        @AuraEnabled public String rawUrl {get;set;}
        @AuraEnabled public String contentsUrl {get;set;}
        @AuraEnabled public String sourceSystem {get;set;} // e.g. GitHub, GitLab, Bitbucket, AzureDevOps, Local, Salesforce
    }

    public class MetadataComponent implements Comparable {
        @AuraEnabled public String componentName {get;set;}
        @AuraEnabled public String apiName {get;set;}
        @AuraEnabled public String metadataType {get;set;}
        @AuraEnabled public String packageXmlType {get;set;}
        @AuraEnabled public String filePath {get;set;}
        @AuraEnabled public String folder {get;set;}
        @AuraEnabled public String extension {get;set;}
        @AuraEnabled public Boolean deployable {get;set;}
        @AuraEnabled public Boolean deleted {get;set;}
        @AuraEnabled public Boolean changed {get;set;}
        @AuraEnabled public Boolean supported {get;set;}
        @AuraEnabled public String status {get;set;}
        
        // System and Git Context
        @AuraEnabled public String repositoryName {get;set;}
        @AuraEnabled public String branchName {get;set;}
        @AuraEnabled public String commitId {get;set;}
        @AuraEnabled public Integer pullRequestNumber {get;set;}
        @AuraEnabled public String pullRequestUrl {get;set;}
        @AuraEnabled public String developerName {get;set;}
        @AuraEnabled public String changedBy {get;set;}
        @AuraEnabled public String lastModified {get;set;}
        @AuraEnabled public String packageMember {get;set;}
        @AuraEnabled public String relativePath {get;set;}
        
        // Classification & Dependency Info
        @AuraEnabled public String metadataCategory {get;set;}
        @AuraEnabled public Integer deploymentOrder {get;set;}
        @AuraEnabled public Boolean hasDependency {get;set;}
        @AuraEnabled public String dependencyType {get;set;}
        @AuraEnabled public String dependencyName {get;set;}
        
        // Validation/Pipeline Flags
        @AuraEnabled public String componentHash {get;set;}
        @AuraEnabled public String namespacePrefix {get;set;}
        @AuraEnabled public Boolean readyForValidation {get;set;}
        @AuraEnabled public Boolean readyForDeployment {get;set;}
        @AuraEnabled public Boolean isRename {get;set;}
        @AuraEnabled public Integer confidenceScore {get;set;}

        public Integer compareTo(Object compareTo) {
            MetadataComponent other = (MetadataComponent) compareTo;
            
            String type1 = this.metadataType != null ? this.metadataType : '';
            String type2 = other.metadataType != null ? other.metadataType : '';
            
            Integer typeCompare = type1.compareTo(type2);
            if (typeCompare != 0) {
                return typeCompare;
            }
            
            String name1 = this.componentName != null ? this.componentName : '';
            String name2 = other.componentName != null ? other.componentName : '';
            return name1.compareTo(name2);
        }
    }

    public class MetadataScannerResult {
        @AuraEnabled public Integer totalFiles {get;set;}
        @AuraEnabled public Integer supportedFiles {get;set;}
        @AuraEnabled public Integer unsupportedFiles {get;set;}
        @AuraEnabled public Integer deployableFiles {get;set;}
        @AuraEnabled public Integer metadataCount {get;set;}
        @AuraEnabled public Long scanTime {get;set;}
        @AuraEnabled public String scannerVersion {get;set;}
        @AuraEnabled public String scanSource {get;set;}
        @AuraEnabled public Map<String, Integer> metadataTypeCounts {get;set;}
        @AuraEnabled public List<String> warnings {get;set;}
        @AuraEnabled public List<String> errors {get;set;}
        @AuraEnabled public List<MetadataComponent> metadataComponents {get;set;}
    }

    // ==========================================
    // METADATA MAPPING CONFIGURATION
    // ==========================================

    public class MetadataMapping {
        public String folderName;
        public String metadataType;
        public String packageXmlType;
        public String extension;
        public Boolean isBundle;
        public String category;
        public Integer deploymentOrder;

        public MetadataMapping(String folderName, String metadataType, String packageXmlType, String extension, Boolean isBundle, String category, Integer deploymentOrder) {
            this.folderName = folderName;
            this.metadataType = metadataType;
            this.packageXmlType = packageXmlType;
            this.extension = extension;
            this.isBundle = isBundle;
            this.category = category;
            this.deploymentOrder = deploymentOrder;
        }
    }

    private static List<MetadataMapping> getMappingsConfiguration() {
        List<MetadataMapping> configs = new List<MetadataMapping>();
        // Code
        configs.add(new MetadataMapping('classes', 'ApexClass', 'ApexClass', '.cls', false, 'Code', 5));
        configs.add(new MetadataMapping('triggers', 'ApexTrigger', 'ApexTrigger', '.trigger', false, 'Code', 5));
        
        // UI
        configs.add(new MetadataMapping('lwc', 'LightningComponentBundle', 'LightningComponentBundle', '', true, 'UI', 6));
        configs.add(new MetadataMapping('aura', 'AuraDefinitionBundle', 'AuraDefinitionBundle', '', true, 'UI', 6));
        configs.add(new MetadataMapping('flexipages', 'FlexiPage', 'FlexiPage', '.flexipage-meta.xml', false, 'UI', 6));
        configs.add(new MetadataMapping('flexipages', 'LightningPage', 'FlexiPage', '.flexipage-meta.xml', false, 'UI', 6));
        configs.add(new MetadataMapping('tabs', 'CustomTab', 'CustomTab', '.tab-meta.xml', false, 'UI', 6));
        configs.add(new MetadataMapping('applications', 'CustomApplication', 'CustomApplication', '.app-meta.xml', false, 'UI', 6));
        configs.add(new MetadataMapping('experiencebundles', 'ExperienceBundle', 'ExperienceBundle', '', true, 'UI', 9));
        configs.add(new MetadataMapping('sites', 'SiteDotCom', 'SiteDotCom', '.site', false, 'UI', 9));
        configs.add(new MetadataMapping('translations', 'Translations', 'Translations', '.translation-meta.xml', false, 'UI', 9));
        
        // Automation
        configs.add(new MetadataMapping('flows', 'Flow', 'Flow', '.flow-meta.xml', false, 'Automation', 7));
        configs.add(new MetadataMapping('approvalProcesses', 'ApprovalProcess', 'ApprovalProcess', '.approvalProcess-meta.xml', false, 'Automation', 7));
        configs.add(new MetadataMapping('workflows', 'Workflow', 'Workflow', '.workflow-meta.xml', false, 'Automation', 7));
        configs.add(new MetadataMapping('assignmentRules', 'AssignmentRule', 'AssignmentRules', '.assignmentRules-meta.xml', false, 'Automation', 7));
        configs.add(new MetadataMapping('escalationRules', 'EscalationRule', 'EscalationRules', '.escalationRules-meta.xml', false, 'Automation', 7));
        
        // Security
        configs.add(new MetadataMapping('permissionsets', 'PermissionSet', 'PermissionSet', '.permissionset-meta.xml', false, 'Security', 8));
        configs.add(new MetadataMapping('profiles', 'Profile', 'Profile', '.profile-meta.xml', false, 'Security', 8));
        configs.add(new MetadataMapping('customPermissions', 'CustomPermission', 'CustomPermission', '.customPermission-meta.xml', false, 'Security', 3));
        
        // Configuration
        configs.add(new MetadataMapping('customMetadata', 'CustomMetadata', 'CustomMetadata', '.md-meta.xml', false, 'Configuration', 4));
        configs.add(new MetadataMapping('roles', 'Role', 'Role', '.role-meta.xml', false, 'Configuration', 1));
        configs.add(new MetadataMapping('queues', 'Queue', 'Queue', '.queue-meta.xml', false, 'Configuration', 1));
        configs.add(new MetadataMapping('globalValueSets', 'GlobalValueSet', 'GlobalValueSet', '.globalValueSet-meta.xml', false, 'Configuration', 1));
        configs.add(new MetadataMapping('standardValueSets', 'StandardValueSet', 'StandardValueSet', '.standardValueSet-meta.xml', false, 'Configuration', 1));
        configs.add(new MetadataMapping('pathAssistants', 'PathAssistant', 'PathAssistant', '.pathAssistant-meta.xml', false, 'Configuration', 9));
        
        // Data
        configs.add(new MetadataMapping('objects', 'CustomObject', 'CustomObject', '.object-meta.xml', false, 'Data', 1));
        configs.add(new MetadataMapping('fields', 'CustomField', 'CustomField', '.field-meta.xml', false, 'Data', 2));
        configs.add(new MetadataMapping('recordTypes', 'RecordType', 'RecordType', '.recordType-meta.xml', false, 'Data', 2));
        configs.add(new MetadataMapping('validationRules', 'ValidationRule', 'ValidationRule', '.validationRule-meta.xml', false, 'Data', 3));
        configs.add(new MetadataMapping('sharingRules', 'SharingRule', 'SharingRules', '.sharingRule-meta.xml', false, 'Data', 7));
        configs.add(new MetadataMapping('sharingRules', 'SharingRule', 'SharingRules', '.sharingRules-meta.xml', false, 'Data', 7));
        configs.add(new MetadataMapping('duplicateRules', 'DuplicateRule', 'DuplicateRule', '.duplicateRule-meta.xml', false, 'Data', 7));
        configs.add(new MetadataMapping('matchingRules', 'MatchingRule', 'MatchingRule', '.matchingRule-meta.xml', false, 'Data', 7));
        configs.add(new MetadataMapping('topicsForObjects', 'TopicsForObjects', 'TopicsForObjects', '.topicsForObjects-meta.xml', false, 'Data', 9));
        
        // Integration
        configs.add(new MetadataMapping('remoteSiteSettings', 'RemoteSiteSetting', 'RemoteSiteSetting', '.remoteSite-meta.xml', false, 'Integration', 4));
        configs.add(new MetadataMapping('namedCredentials', 'NamedCredential', 'NamedCredential', '.namedCredential-meta.xml', false, 'Integration', 4));
        configs.add(new MetadataMapping('connectedApps', 'ConnectedApp', 'ConnectedApp', '.connectedApp-meta.xml', false, 'Integration', 9));
        configs.add(new MetadataMapping('networks', 'Network', 'Network', '.network-meta.xml', false, 'Integration', 9));
        
        // Other
        configs.add(new MetadataMapping('staticresources', 'StaticResource', 'StaticResource', '.resource', false, 'Other', 5));
        configs.add(new MetadataMapping('labels', 'CustomLabel', 'CustomLabels', '.labels-meta.xml', false, 'Other', 5));
        configs.add(new MetadataMapping('email', 'EmailTemplate', 'EmailTemplate', '.email', false, 'Other', 5));
        configs.add(new MetadataMapping('reports', 'Report', 'Report', '.report', false, 'Other', 5));
        configs.add(new MetadataMapping('dashboards', 'Dashboard', 'Dashboard', '.dashboard', false, 'Other', 5));

        return configs;
    }

    public static Map<String, List<MetadataMapping>> getFolderMappings() {
        Map<String, List<MetadataMapping>> m = new Map<String, List<MetadataMapping>>();
        for (MetadataMapping mapping : getMappingsConfiguration()) {
            String key = mapping.folderName.toLowerCase();
            if (!m.containsKey(key)) {
                m.put(key, new List<MetadataMapping>());
            }
            m.get(key).add(mapping);
        }
        return m;
    }

    public static Map<String, MetadataMapping> getPackageMappings() {
        Map<String, MetadataMapping> m = new Map<String, MetadataMapping>();
        for (MetadataMapping mapping : getMappingsConfiguration()) {
            String key = mapping.metadataType.toLowerCase();
            if (!m.containsKey(key)) {
                m.put(key, mapping);
            }
        }
        return m;
    }

    // ==========================================
    // PUBLIC ENTRY POINT
    // ==========================================

    public static MetadataScannerResult discoverMetadata(List<ChangedFile> files) {
        return discoverMetadata(files, 'Manual');
    }

    public static MetadataScannerResult discoverMetadata(List<ChangedFile> files, String scanSource) {
        Long startTime = System.currentTimeMillis();
        MetadataScannerResult result = new MetadataScannerResult();
        result.scannerVersion = '1.0';
        result.scanSource = String.isNotBlank(scanSource) ? scanSource : 'Manual';
        result.warnings = new List<String>();
        result.errors = new List<String>();
        result.metadataComponents = new List<MetadataComponent>();
        result.metadataTypeCounts = new Map<String, Integer>();
        
        if (files == null) {
            result.totalFiles = 0;
            result.supportedFiles = 0;
            result.unsupportedFiles = 0;
            result.deployableFiles = 0;
            result.metadataCount = 0;
            result.scanTime = System.currentTimeMillis() - startTime;
            postProcessMetadata(result);
            return result;
        }
        
        result.totalFiles = files.size();
        
        // 1. Scan files
        List<MetadataComponent> scannedComps = scanFiles(files, result);
        
        // 2. Remove duplicates
        List<MetadataComponent> deduplicated = removeDuplicates(scannedComps);
        
        // 3. Sort components
        sortMetadata(deduplicated);
        
        // 4. Fill stats & results
        result.metadataComponents = deduplicated;
        result.metadataCount = deduplicated.size();
        
        Integer supported = 0;
        Integer unsupported = 0;
        Integer deployable = 0;
        
        for (MetadataComponent comp : deduplicated) {
            if (comp.supported == true) {
                supported++;
            } else {
                unsupported++;
            }
            if (comp.deployable == true) {
                deployable++;
            }
            
            // Count type occurrences
            if (String.isNotBlank(comp.metadataType)) {
                String typeName = comp.metadataType;
                Integer currentCount = result.metadataTypeCounts.containsKey(typeName) ? result.metadataTypeCounts.get(typeName) : 0;
                result.metadataTypeCounts.put(typeName, currentCount + 1);
            }
        }
        
        result.supportedFiles = supported;
        result.unsupportedFiles = unsupported;
        result.deployableFiles = deployable;
        
        // 5. Post Process hook
        postProcessMetadata(result);
        
        result.scanTime = System.currentTimeMillis() - startTime;
        return result;
    }

    // ==========================================
    // PRIVATE SCANNER & PARSING HELPER METHODS
    // ==========================================

    private static List<MetadataComponent> scanFiles(List<ChangedFile> files, MetadataScannerResult result) {
        List<MetadataComponent> comps = new List<MetadataComponent>();
        for (ChangedFile file : files) {
            if (file == null || String.isBlank(file.filename)) {
                continue;
            }
            if (shouldIgnoreFile(file.filename)) {
                result.warnings.add('File is ignored based on path rules: ' + file.filename);
                continue;
            }
            try {
                MetadataComponent comp = buildMetadataComponent(file);
                comps.add(comp);
            } catch (Exception e) {
                result.errors.add('Failed to scan file ' + file.filename + ': ' + e.getMessage());
            }
        }
        return comps;
    }

    private static MetadataComponent buildMetadataComponent(ChangedFile file) {
        MetadataComponent comp = new MetadataComponent();
        comp.filePath = file.filename;
        comp.relativePath = file.filename;
        comp.status = file.status;
        comp.componentHash = file.sha;
        comp.isRename = (file.status != null && file.status.equalsIgnoreCase('renamed')) || String.isNotBlank(file.previousFilename);
        
        comp.changed = true;
        comp.deleted = (file.status != null && (file.status.equalsIgnoreCase('removed') || file.status.equalsIgnoreCase('deleted')));
        comp.readyForValidation = true;
        comp.readyForDeployment = true;
        
        String folderSegment = extractFolder(file.filename);
        comp.folder = folderSegment;
        comp.extension = extractExtension(file.filename);
        comp.metadataType = detectMetadataType(file.filename);
        comp.packageXmlType = detectPackageXmlType(comp.metadataType);
        
        comp.componentName = extractComponentName(file.filename, comp.metadataType);
        comp.apiName = comp.componentName;
        comp.packageMember = comp.componentName;
        
        if (String.isNotBlank(comp.metadataType)) {
            Map<String, MetadataMapping> packageMappings = getPackageMappings();
            MetadataMapping mapping = packageMappings.get(comp.metadataType.toLowerCase());
            if (mapping != null) {
                comp.metadataCategory = mapping.category;
                comp.deploymentOrder = mapping.deploymentOrder;
            }
        }
        
        if (comp.metadataCategory == null) {
            comp.metadataCategory = 'Other';
        }
        if (comp.deploymentOrder == null) {
            comp.deploymentOrder = 99;
        }
        
        comp.supported = isSupported(comp.metadataType);
        comp.deployable = isDeployable(comp);
        comp.confidenceScore = calculateConfidenceScore(comp, folderSegment);
        
        detectDependencies(comp);
        
        return comp;
    }

    private static String detectMetadataType(String filePath) {
        if (String.isBlank(filePath) || shouldIgnoreFile(filePath)) {
            return null;
        }
        String normalizedPath = filePath.replace('\\', '/');
        List<String> segments = normalizedPath.split('/');
        Map<String, List<MetadataMapping>> folderMappings = getFolderMappings();
        
        for (Integer i = 0; i < segments.size(); i++) {
            String segment = segments[i].toLowerCase();
            if (folderMappings.containsKey(segment)) {
                if (segment.equals('objects')) {
                    if (i + 1 < segments.size()) {
                        if (i + 2 < segments.size()) {
                            String subFolder = segments[i + 2].toLowerCase();
                            if (subFolder.equals('fields')) {
                                return 'CustomField';
                            } else if (subFolder.equals('recordtypes')) {
                                return 'RecordType';
                            } else if (subFolder.equals('validationrules')) {
                                return 'ValidationRule';
                            } else if (subFolder.equals('sharingrules')) {
                                return 'SharingRule';
                            }
                        }
                        return 'CustomObject';
                    }
                } else {
                    List<MetadataMapping> mappings = folderMappings.get(segment);
                    if (mappings != null && !mappings.isEmpty()) {
                        return mappings[0].metadataType;
                    }
                }
            }
        }
        return null;
    }

    private static String detectPackageXmlType(String metadataType) {
        if (String.isBlank(metadataType)) {
            return null;
        }
        Map<String, MetadataMapping> packageMappings = getPackageMappings();
        MetadataMapping mapping = packageMappings.get(metadataType.toLowerCase());
        if (mapping != null) {
            return mapping.packageXmlType;
        }
        return null;
    }

    private static String extractComponentName(String filePath, String metadataType) {
        if (String.isBlank(filePath)) {
            return '';
        }
        String normalizedPath = filePath.replace('\\', '/');
        List<String> segments = normalizedPath.split('/');
        
        Integer folderIdx = -1;
        Map<String, List<MetadataMapping>> folderMappings = getFolderMappings();
        for (Integer i = 0; i < segments.size(); i++) {
            if (folderMappings.containsKey(segments[i].toLowerCase())) {
                folderIdx = i;
                break;
            }
        }
        
        if (folderIdx == -1) {
            return stripExtension(segments[segments.size() - 1]);
        }
        
        String folderSegment = segments[folderIdx].toLowerCase();
        Boolean isBundleType = false;
        
        if (String.isNotBlank(metadataType)) {
            Map<String, MetadataMapping> packageMappings = getPackageMappings();
            MetadataMapping mapping = packageMappings.get(metadataType.toLowerCase());
            if (mapping != null && mapping.isBundle) {
                isBundleType = true;
            }
        }
        
        if (isBundleType) {
            if (folderIdx + 1 < segments.size()) {
                return segments[folderIdx + 1];
            }
        }
        
        if (folderSegment.equals('objects')) {
            if (folderIdx + 1 < segments.size()) {
                String objectName = segments[folderIdx + 1];
                if (folderIdx + 2 < segments.size()) {
                    String subFolder = segments[folderIdx + 2].toLowerCase();
                    if (subFolder.equals('fields') || 
                        subFolder.equals('recordtypes') || 
                        subFolder.equals('validationrules') || 
                        subFolder.equals('sharingrules')) {
                        if (folderIdx + 3 < segments.size()) {
                            String fileName = segments[folderIdx + 3];
                            return objectName + '.' + stripExtension(fileName);
                        }
                    }
                }
                return objectName;
            }
        }
        
        if (folderSegment.equals('staticresources')) {
            if (folderIdx + 1 < segments.size()) {
                return stripExtension(segments[folderIdx + 1]);
            }
        }
        
        if (folderSegment.equals('email') || 
            folderSegment.equals('reports') || 
            folderSegment.equals('dashboards')) {
            List<String> parts = new List<String>();
            for (Integer i = folderIdx + 1; i < segments.size(); i++) {
                parts.add(segments[i]);
            }
            if (!parts.isEmpty()) {
                String joined = String.join(parts, '/');
                return stripExtension(joined);
            }
        }
        
        return stripExtension(segments[segments.size() - 1]);
    }

    private static String extractFolder(String filePath) {
        if (String.isBlank(filePath)) {
            return '';
        }
        String normalizedPath = filePath.replace('\\', '/');
        List<String> segments = normalizedPath.split('/');
        Map<String, List<MetadataMapping>> folderMappings = getFolderMappings();
        for (Integer i = 0; i < segments.size(); i++) {
            if (folderMappings.containsKey(segments[i].toLowerCase())) {
                return segments[i];
            }
        }
        return '';
    }

    private static String extractExtension(String filePath) {
        if (String.isBlank(filePath)) {
            return '';
        }
        String fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
        fileName = fileName.substring(fileName.lastIndexOf('\\') + 1);
        
        if (fileName.endsWithIgnoreCase('-meta.xml')) {
            Integer dotIdx = fileName.indexOf('.');
            if (dotIdx >= 0) {
                return fileName.substring(dotIdx + 1);
            }
            return '';
        } else {
            Integer dotIdx = fileName.lastIndexOf('.');
            if (dotIdx >= 0) {
                return fileName.substring(dotIdx + 1);
            }
            return '';
        }
    }

    private static Boolean isDeployable(MetadataComponent comp) {
        if (comp == null) {
            return false;
        }
        if (!isSupported(comp.metadataType)) {
            return false;
        }
        if (String.isBlank(comp.filePath) || shouldIgnoreFile(comp.filePath)) {
            return false;
        }
        if (String.isBlank(comp.metadataType) || String.isBlank(comp.packageXmlType)) {
            return false;
        }
        return true;
    }

    private static Boolean isSupported(String metadataType) {
        if (String.isBlank(metadataType)) {
            return false;
        }
        Map<String, MetadataMapping> packageMappings = getPackageMappings();
        return packageMappings.containsKey(metadataType.toLowerCase());
    }

    public static Boolean shouldIgnoreFile(String filePath) {
        if (String.isBlank(filePath)) {
            return true;
        }
        String path = filePath.toLowerCase().replace('\\', '/');
        List<String> ignoredKeywords = new List<String>{
            '/readme', 'readme.md', 'readme.txt',
            'package.json', 'package-lock.json',
            '/node_modules/', 'node_modules/',
            '/scripts/', 'scripts/',
            '/images/', 'images/',
            '/documents/', 'documents/',
            '/.github/', '.github/',
            '/.vscode/', '.vscode/',
            '/logs/', 'logs/',
            'test report', 'test_report', 'test-report',
            '/temp/', 'temp/', '/tmp/', 'tmp/'
        };
        
        for (String keyword : ignoredKeywords) {
            if (path.contains(keyword) || path.startsWith(keyword) || path.endsWith(keyword)) {
                return true;
            }
        }
        return false;
    }

    private static Integer calculateConfidenceScore(MetadataComponent comp, String folderSegment) {
        if (comp == null) {
            return 0;
        }
        if (!comp.supported) {
            return 50;
        }
        if (comp.deployable) {
            Map<String, MetadataMapping> packageMappings = getPackageMappings();
            MetadataMapping mapping = packageMappings.get(comp.metadataType.toLowerCase());
            if (mapping != null) {
                if (mapping.isBundle) {
                    return 100;
                }
                if (String.isNotBlank(mapping.extension) && comp.extension != null && comp.extension.toLowerCase().contains(mapping.extension.toLowerCase().replace('.', ''))) {
                    return 100;
                }
                return 90;
            }
            return 95;
        }
        return 50;
    }

    private static void detectDependencies(MetadataComponent comp) {
        if (comp == null) {
            return;
        }
        comp.hasDependency = false;
        comp.dependencyType = '';
        comp.dependencyName = '';
        
        if (String.isBlank(comp.filePath)) {
            return;
        }
        
        String normalizedPath = comp.filePath.replace('\\', '/');
        List<String> segments = normalizedPath.split('/');
        Integer objectsIdx = -1;
        for (Integer i = 0; i < segments.size(); i++) {
            if (segments[i].equalsIgnoreCase('objects')) {
                objectsIdx = i;
                break;
            }
        }
        
        if (objectsIdx != -1 && objectsIdx + 1 < segments.size()) {
            String objectName = segments[objectsIdx + 1];
            if (comp.metadataType != null && (
                comp.metadataType.equalsIgnoreCase('CustomField') ||
                comp.metadataType.equalsIgnoreCase('RecordType') ||
                comp.metadataType.equalsIgnoreCase('ValidationRule') ||
                comp.metadataType.equalsIgnoreCase('SharingRule')
            )) {
                comp.hasDependency = true;
                comp.dependencyType = 'CustomObject';
                comp.dependencyName = objectName;
            }
        }
    }

    private static List<MetadataComponent> removeDuplicates(List<MetadataComponent> comps) {
        if (comps == null || comps.isEmpty()) {
            return new List<MetadataComponent>();
        }
        
        Map<String, List<MetadataComponent>> grouped = new Map<String, List<MetadataComponent>>();
        for (MetadataComponent comp : comps) {
            String key;
            if (String.isNotBlank(comp.metadataType) && String.isNotBlank(comp.componentName)) {
                key = comp.metadataType.toLowerCase() + '##' + comp.componentName.toLowerCase();
            } else {
                key = 'invalid##' + comp.filePath.toLowerCase();
            }
            
            if (!grouped.containsKey(key)) {
                grouped.put(key, new List<MetadataComponent>());
            }
            grouped.get(key).add(comp);
        }
        
        List<MetadataComponent> deduplicated = new List<MetadataComponent>();
        for (String key : grouped.keySet()) {
            List<MetadataComponent> compGroup = grouped.get(key);
            if (compGroup.size() == 1) {
                deduplicated.add(compGroup[0]);
            } else {
                deduplicated.add(mergeMetadataComponents(compGroup));
            }
        }
        return deduplicated;
    }

    private static MetadataComponent mergeMetadataComponents(List<MetadataComponent> compGroup) {
        MetadataComponent primary = compGroup[0];
        for (MetadataComponent comp : compGroup) {
            if (String.isNotBlank(comp.filePath) && !comp.filePath.endsWithIgnoreCase('-meta.xml')) {
                primary = comp;
                break;
            }
        }
        
        Boolean anyChanged = false;
        Boolean allDeleted = true;
        Boolean anyDeployable = false;
        Boolean anySupported = false;
        
        for (MetadataComponent comp : compGroup) {
            if (comp.changed == true) {
                anyChanged = true;
            }
            if (comp.deleted == false) {
                allDeleted = false;
            }
            if (comp.deployable == true) {
                anyDeployable = true;
            }
            if (comp.supported == true) {
                anySupported = true;
            }
        }
        
        MetadataComponent merged = new MetadataComponent();
        merged.componentName = primary.componentName;
        merged.apiName = primary.apiName;
        merged.metadataType = primary.metadataType;
        merged.packageXmlType = primary.packageXmlType;
        merged.filePath = primary.filePath;
        merged.folder = primary.folder;
        merged.extension = primary.extension;
        merged.deployable = anyDeployable;
        merged.deleted = allDeleted;
        merged.changed = anyChanged;
        merged.supported = anySupported;
        merged.status = primary.status;
        
        merged.repositoryName = primary.repositoryName;
        merged.branchName = primary.branchName;
        merged.commitId = primary.commitId;
        merged.pullRequestNumber = primary.pullRequestNumber;
        merged.pullRequestUrl = primary.pullRequestUrl;
        merged.developerName = primary.developerName;
        merged.changedBy = primary.changedBy;
        merged.lastModified = primary.lastModified;
        merged.packageMember = primary.packageMember;
        merged.relativePath = primary.relativePath;
        merged.metadataCategory = primary.metadataCategory;
        merged.deploymentOrder = primary.deploymentOrder;
        merged.hasDependency = primary.hasDependency;
        merged.dependencyType = primary.dependencyType;
        merged.dependencyName = primary.dependencyName;
        merged.componentHash = primary.componentHash;
        merged.namespacePrefix = primary.namespacePrefix;
        merged.readyForValidation = primary.readyForValidation;
        merged.readyForDeployment = primary.readyForDeployment;
        merged.isRename = primary.isRename;
        merged.confidenceScore = primary.confidenceScore;
        
        return merged;
    }

    private static void sortMetadata(List<MetadataComponent> comps) {
        if (comps != null) {
            comps.sort();
        }
    }

    private static String stripExtension(String name) {
        if (String.isBlank(name)) {
            return name;
        }
        if (name.endsWithIgnoreCase('-meta.xml')) {
            name = name.substring(0, name.length() - 9);
        }
        Integer lastDot = name.lastIndexOf('.');
        if (lastDot > 0) {
            name = name.substring(0, lastDot);
        }
        return name;
    }

    // ==========================================
    // FUTURE HOOK / EXTENSION POINT
    // ==========================================

    public static void postProcessMetadata(MetadataScannerResult result) {
        // Empty post-processing hook for future dependency resolvers, AI classifiers, or package builders.
    }
}