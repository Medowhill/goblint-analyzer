// PARAM: --enable allfuns --set ana.activated "['base','baseflag','escape']"

int glob1 = 5;
int glob2 = 7;

int f() {
  glob1 = 5;
  return 0;
}

int g() {
  assert(glob1 == 5);
  assert(glob2 == 7);
  return 0;
}
