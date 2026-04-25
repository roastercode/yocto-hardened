# munge.key — TEST KEY, NOT FOR PRODUCTION

This file is a 1024-byte random key used by the MUNGE authentication
service in the reference QEMU HPC cluster (master + 3 compute nodes).

It is committed to this repository **deliberately** because the
cluster is a test/dev environment and the key must be identical
across all nodes for cross-node authentication to work.

## NEVER USE THIS KEY IN PRODUCTION

Any production deployment must:
1. Generate its own key on a secure host:
     dd if=/dev/urandom of=munge.key bs=1 count=1024
     chmod 0400 munge.key
2. Distribute it out-of-band (encrypted channel, not git)
3. Set HPC_MUNGE_KEY_FILE to point to the production key path
4. Never commit production keys to any repository

## Regenerating the test key

If for any reason this key is compromised or needs rotation:

    cd recipes-core/images/files/
    dd if=/dev/urandom of=munge.key bs=1 count=1024 status=none
    chmod 0400 munge.key
    git add munge.key && git commit -S -m "munge: rotate test key"

Then rebuild all 4 cluster images and redeploy.
