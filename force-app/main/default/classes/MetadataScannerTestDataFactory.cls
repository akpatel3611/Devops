@isTest
public class MetadataScannerTestDataFactory {

    public static MetadataScannerService.ChangedFile createChangedFile(String filename, String status) {
        return createChangedFile(filename, status, 'GitHub');
    }

    public static MetadataScannerService.ChangedFile createChangedFile(String filename, String status, String sourceSystem) {
        MetadataScannerService.ChangedFile file = new MetadataScannerService.ChangedFile();
        file.filename = filename;
        file.status = status;
        file.sha = 'abc123sha_' + Integer.valueOf(Math.random() * 10000);
        file.blobUrl = 'https://github.com/test/repo/blob/main/' + filename;
        file.rawUrl = 'https://github.com/test/repo/raw/main/' + filename;
        file.contentsUrl = 'https://api.github.com/repos/test/repo/contents/' + filename;
        file.sourceSystem = sourceSystem;
        return file;
    }

    public static MetadataScannerService.ChangedFile createRenamedFile(String filename, String previousFilename) {
        return createRenamedFile(filename, previousFilename, 'GitHub');
    }

    public static MetadataScannerService.ChangedFile createRenamedFile(String filename, String previousFilename, String sourceSystem) {
        MetadataScannerService.ChangedFile file = new MetadataScannerService.ChangedFile();
        file.filename = filename;
        file.status = 'renamed';
        file.previousFilename = previousFilename;
        file.sha = 'abc123sha_rename';
        file.sourceSystem = sourceSystem;
        return file;
    }

    public static List<MetadataScannerService.ChangedFile> createBulkFiles(Integer count, String folder, String extension) {
        List<MetadataScannerService.ChangedFile> files = new List<MetadataScannerService.ChangedFile>();
        for (Integer i = 0; i < count; i++) {
            String filename = 'force-app/main/default/' + folder + '/TestComponent' + i + extension;
            files.add(createChangedFile(filename, 'added'));
        }
        return files;
    }
}