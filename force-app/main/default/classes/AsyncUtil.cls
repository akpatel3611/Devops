public with sharing class AsyncUtil {

    public static void waitForSeconds(
        Integer seconds
    ) {

        Long startTime =
            DateTime.now().getTime();

        while (

            DateTime.now().getTime()
            <
            startTime + (seconds * 1000)

        ) {

        }
    }
}