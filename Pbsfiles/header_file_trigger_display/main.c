#include <stdio.h>
#include <stdlib.h>

#include "common.h"
#include "common2.h"
#include "common3.h"

void foo(void) ;
void bar(void) ;
void baz(int) ;
void PrintHelloWorld(void) ;

void foo(void) 
{
bar();
}

void bar(void) 
{
	foo();
	baz(1);
}

void baz(int x) 
{
	foo();
}


int main(void)
{

foo() ;

baz(3) ;

return(0) ;
}



