//PARAM: --enable allfuns --enable ana.library  --set ana.activated "['base','mallocWrapperTypeBased']"
#include <stdlib.h>

int f(int *x){
    return *x;
}

int main(){
    void *tmp = malloc(sizeof(char) * 100);
    int top;
    f((int*) tmp);
    return 2;
}