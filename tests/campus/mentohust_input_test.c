#define NO_NOTIFY 1
#define NO_DYLOAD 1
#include <assert.h>
#include <string.h>
#include <termios.h>
static tcflag_t restored;
int tcgetattr(int fd, struct termios *t){memset(t,0,sizeof(*t));t->c_lflag=ICANON;return 0;}
int tcsetattr(int fd,int action,const struct termios *t){restored=t->c_lflag;return 0;}
#include "myconfig.c"
int main(int argc,char **argv)
{
    char value[65];assert(argc==2);
    int expected=atoi(argv[1]);int result=getpasswd(value);
    assert((result==0)==expected);
    assert(restored==ICANON);
    if(!expected)assert(!value[0]);
    puts("PASS");return 0;
}
