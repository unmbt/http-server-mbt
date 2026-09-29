# Third-party notices

Original http-server-mbt code is Copyright (c) 2026 UnMoonBit and licensed
under MIT. That license does not replace the licenses of the components below.
Preserve their copyright, license and attribution notices when redistributing
source or binaries. Inclusion of a notice does not mean every build uses that
component: Thin omits TLS and the Mozilla trust store.

| Component | Source / version | License and scope |
|---|---|---|
| moonbitlang/async | https://github.com/moonbitlang/async, 0.21.3 | Apache-2.0; Native async I/O |
| MoonBit core and Native runtime | Actual compiler installation recorded in BUILD-PROVENANCE.txt | Apache-2.0, plus core NOTICE; standard library/runtime incorporated into binaries |
| simdutf | https://github.com/simdutf/simdutf; object supplied by the MoonBit toolchain | MIT option; notice text pinned separately in third_party/PROVENANCE.md |
| libbacktrace | MoonBit toolchain backtrace.h | BSD-3-Clause; retained conservatively with runtime notices |
| musl | Linux static CLI build's installed musl package | MIT and component notices; actual Debian copyright accompanies Linux candidates |
| Mbed TLS / TF-PSA-Crypto | https://github.com/Mbed-TLS/mbedtls, 4.2.0 / 1.2.0 | Apache-2.0 OR GPL-2.0-or-later; **this distribution selects Apache-2.0** |
| Mozilla certificate data | https://curl.se/ca/cacert-2025-09-09.pem | MPL-2.0; Full trust store and its generated source |
| Node-API headers | Node.js v22.14.0; import library provenance recorded separately | MIT and accompanying Node notices; addon build inputs |
| http-party/http-server | Commit 0d3b7bb5b6e8a59fd450ae2dca65870009cfcd8b | MIT; migrated tests, fixtures and any adapted material |
| libevent | 2.1.12-stable | BSD-3-Clause and accompanying MIT/ISC notices; C examples only |

Mbed TLS configuration headers were modified by
scripts/maintenance/vendor_tls.mbtx: managed feature overrides and ASCII
comment normalization. Their original notices and modification markers are
retained. The Apache option applies to both TLS and TF-PSA-Crypto; no GPL
option is elected for them by this project.

## Obtaining the MPL-covered source

The full/cacert.pem resource and full/ca_bundle.mbt generated from it remain
under MPL-2.0, including modifications to these files. Other project files
retain their own licenses. Binary and npm license bundles include these two
files and embed_ca.mbtx in mozilla-source/, together with CA-PROVENANCE.md and
Mozilla-MPL-2.0.txt. This supplies the covered source directly, without a
network download. The same files are in the release's moonbit-source.tar.gz
and in https://github.com/unmbt/http-server-mbt under the corresponding release
tag. Do not remove the covered-source files when redistributing Full.

## Where to find the texts

In a source checkout: third_party/, the TLS LICENSE files, full/ and
c_abi/node/LICENSE-NODE.txt contain the fixed third-party materials. Installed
MoonBit/async dependencies retain their own notices. Builds collect the
actual toolchain's notices, version and runtime object hashes in licenses/.
Binary archives and npm packages include licenses/; containers include
/usr/share/licenses/http-server-mbt/. Standalone release executables must be
redistributed with their platform license bundle (licenses-<platform>.tar.gz),
or use the self-contained cli-<flavor>-<platform>.tar.gz archive.

The libevent example distribution includes its upstream LICENSE. Express
5.1.0 and its npm lockfile dependencies use MIT/ISC/BSD licenses; FastAPI,
Starlette, Uvicorn and the Python requirements use MIT/BSD/Apache/PSF licenses.
These dependencies are installed by their package managers and are not
bundled into the server engine. If you redistribute node_modules or a Python
environment, retain each installed distribution's license and metadata too.
Distroless base-layer Debian notices remain in that image; scratch has no
base-layer dependencies. Neither base replaces the program's license bundle.
