public class StringListTest {
    public static List<String> generateStringList(Integer count) {
        List<String> result = new List<String>();
        for (Integer i = 0; i < count; i++) {
            result.add('Test ' + i);
        }
        return result;
    }
}