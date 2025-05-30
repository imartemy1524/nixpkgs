{
  lib,
  fetchFromGitLab,
  buildDunePackage,
  integers_stubs_js,
  ctypes,
  ppx_expect,
  js_of_ocaml-compiler,
  nodejs,
  stdenv,
}:

buildDunePackage rec {
  pname = "ctypes_stubs_js";
  version = "0.1";

  minimalOCamlVersion = "4.08";

  src = fetchFromGitLab {
    owner = "nomadic-labs";
    repo = pname;
    rev = version;
    hash = "sha256-OJIzg2hnwkXkQHd4bRR051eLf4HNWa/XExxbj46SyUs=";
  };

  propagatedBuildInputs = [ integers_stubs_js ];
  nativeCheckInputs = [
    nodejs
    (
      if lib.versionAtLeast js_of_ocaml-compiler.version "6.0" then
        js_of_ocaml-compiler.override { version = "5.9.1"; }
      else
        js_of_ocaml-compiler
    )
  ];
  checkInputs = [
    ctypes
    ppx_expect
  ];
  doCheck = !(stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isAarch64);

  meta = {
    description = "Js_of_ocaml Javascript stubs for the OCaml ctypes library";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ bezmuth ];
    homepage = "https://gitlab.com/nomadic-labs/ctypes_stubs_js";
  };
}
