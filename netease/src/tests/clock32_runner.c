#include <stdio.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"
int main(int argc,char **argv) {
  if(argc!=3 || sizeof(lua_Integer)!=4 || sizeof(lua_Number)!=4) {
    fprintf(stderr,"Need int32/float32 Lua, app root, test script\n");return 2;
  }
  lua_State *L=luaL_newstate();
  if(!L)return 3;
  luaL_openlibs(L);
  lua_pushstring(L,argv[1]);lua_setglobal(L,"ROOT");
  int status=luaL_dofile(L,argv[2]);
  if(status)fprintf(stderr,"%s\n",lua_tostring(L,-1));
  lua_close(L);return status?1:0;
}
