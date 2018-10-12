{ stdenv, fetchurl, zlib, postgresql, gmp, autoPatchelfHook }:

stdenv.mkDerivation rec {
  name = "postgrest-${version}";
  version = "v5.1.0";

  src = fetchurl {
    url = "https://github.com/PostgREST/postgrest/releases/download/${version}/postgrest-${version}-ubuntu.tar.xz";
    sha256 = "1lqmf97clqccixjph52nxplwvv3g6j102d4s0f85a0crwy3pawxn";
  };

  unpackCmd = ''
    mkdir postgrest
    tar xf "$src" -C postgrest
  '';

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ zlib postgresql gmp ];
  dontStrip = true;

  installPhase = ''
    ls -l
    mkdir -p $out/bin
    cp ./postgrest $out/bin/
  '';
}
