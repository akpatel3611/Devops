public class futureMethodDemo {
    public futureMethodDemo(){
     System.debug('I am in futureExample Constructor methode');  
        method1();
        method2();
        method3();
        method4(5, 'raj');
        method5();
    }
    
    public void method1(){
     System.debug('I am in methode1'); 
    }
    
    public void method2(){
        System.debug('I am in static void methode2');
    }
    @future
    public static void method3(){
        System.debug('I am in static void methode3');
        //method4();
    }
    @future
    public static void method4(Integer i, String s){
        System.debug('I am in static void methode4');
        System.debug('i =='+ i);
        System.debug('i =='+ s);
    }
    public static void method5(){
        System.debug('I am in static void methode5');
    }
}