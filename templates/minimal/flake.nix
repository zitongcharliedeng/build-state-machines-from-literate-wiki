{
  inputs.lsmw.url = "github:zitongcharliedeng/build-state-machines-from-literate-wiki/dev";
  outputs = { self, lsmw, ... }: lsmw.lib.minimalFlake { src = self; };
}
