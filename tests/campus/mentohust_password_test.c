#include "myfunc.c"
#include <assert.h>
char password[65];
unsigned startMode;
int main(void){
 unsigned char seed[16]={0},expected[91],digest[16];
 memset(password,'p',64);password[64]=0;startMode=2;
 expected[0]=37;memcpy(expected+1,password,64);memcpy(expected+65,"xxghlmxhzb",10);memcpy(expected+75,seed,16);
 memcpy(digest,ComputeHash(expected,sizeof(expected)),16);
 assert(memcmp(checkPass(37,seed,16),digest,16)==0);puts("PASS");return 0;
}
