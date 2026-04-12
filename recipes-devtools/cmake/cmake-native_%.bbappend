CFLAGS:append:class-native = " -std=gnu17"
CXXFLAGS:append:class-native = " -std=gnu++17"
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append = " file://fix-cstdint.py"

python do_patch:append:class-native() {
    import subprocess, os
    script = os.path.join(d.getVar('WORKDIR'), 'fix-cstdint.py')
    header = os.path.join(d.getVar('S'), 
        'Utilities/cmcppdap/include/dap/network.h')
    if os.path.exists(script) and os.path.exists(header):
        subprocess.run(['python3', script, header], check=True)
}
