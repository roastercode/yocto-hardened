// SPDX-License-Identifier: GPL-2.0-only
/*
 * FTRFS — EDAC layer: CRC32 + Reed-Solomon FEC
 * Author: Aurelien DESBRIERES <aurelien@hackers.camp>
 *
 * Reed-Solomon encoding/decoding uses the kernel's lib/reed_solomon
 * library (RS(255,239) over GF(2^8), primitive polynomial 0x187).
 * This avoids duplicating well-tested RS code already present in the
 * kernel (used by NAND MTD, DVB, etc.) and addresses the concern raised
 * during review (Eric Biggers, linux-fsdevel, April 2026).
 *
 * RS parameters:
 *   FTRFS_RS_SYMSIZE = 8         (GF(2^8))
 *   FTRFS_RS_FCR     = 0         (first consecutive root)
 *   FTRFS_RS_PRIM    = 1         (primitive element)
 *   FTRFS_RS_NROOTS  = FTRFS_RS_PARITY = 16 (parity symbols)
 *   data per subblock: FTRFS_SUBBLOCK_DATA = 239 bytes
 *   codeword length:   255 bytes (FTRFS_SUBBLOCK_TOTAL)
 */

#include <linux/kernel.h>
#include <linux/crc32.h>
#include <linux/slab.h>
#include <linux/rslib.h>
#include "ftrfs.h"

/* RS codec handle — allocated once at module init */
static struct rs_control *ftrfs_rs_ctrl;

/*
 * ftrfs_rs_init_tables — initialize the RS codec
 * Called once from ftrfs_init() before any mount.
 */
void ftrfs_rs_init_tables(void)
{
	/*
	 * init_rs(symsize, gfpoly, fcr, prim, nroots)
	 * symsize = 8      -> GF(2^8)
	 * gfpoly  = 0x187  -> primitive polynomial x^8+x^7+x^2+x+1
	 * fcr     = 0      -> first consecutive root
	 * prim    = 1      -> primitive element alpha
	 * nroots  = 16     -> 16 parity symbols, corrects up to 8 errors
	 */
	ftrfs_rs_ctrl = init_rs(8, 0x187, 0, 1, FTRFS_RS_PARITY);
	if (!ftrfs_rs_ctrl)
		pr_err("ftrfs: failed to initialize RS codec\n");
	else
		pr_debug("ftrfs: RS codec initialized (RS(%d,%d))\n",
			 FTRFS_SUBBLOCK_TOTAL, FTRFS_SUBBLOCK_DATA);
}

/*
 * ftrfs_rs_exit — release the RS codec at module exit
 */
void ftrfs_rs_exit_tables(void)
{
	if (ftrfs_rs_ctrl) {
		free_rs(ftrfs_rs_ctrl);
		ftrfs_rs_ctrl = NULL;
	}
}

/*
 * ftrfs_rs_encode — encode FTRFS_SUBBLOCK_DATA bytes, produce parity
 * @data:   input data (FTRFS_SUBBLOCK_DATA bytes)
 * @parity: output parity (FTRFS_RS_PARITY bytes)
 *
 * encode_rs8() takes data as u8* directly; only par is u16*.
 */
int ftrfs_rs_encode(u8 *data, u8 *parity)
{
	u16 par[FTRFS_RS_PARITY];
	int i;

	if (!ftrfs_rs_ctrl)
		return -EINVAL;

	memset(par, 0, sizeof(par));
	encode_rs8(ftrfs_rs_ctrl, data, FTRFS_SUBBLOCK_DATA, par, 0);

	for (i = 0; i < FTRFS_RS_PARITY; i++)
		parity[i] = (u8)par[i];

	return 0;
}

/*
 * ftrfs_rs_decode — decode and correct a RS(255,239) codeword in place
 * @data:   data bytes (FTRFS_SUBBLOCK_DATA), corrected in place on success
 * @parity: parity bytes (FTRFS_RS_PARITY)
 *
 * decode_rs8() takes data as u8* directly; par is u16*.
 * Returns 0 if no errors or errors corrected successfully,
 * -EBADMSG if uncorrectable (more than FTRFS_RS_PARITY/2 symbol errors).
 */
int ftrfs_rs_decode(u8 *data, u8 *parity)
{
	u16 par[FTRFS_RS_PARITY];
	int i, nerr;

	if (!ftrfs_rs_ctrl)
		return -EINVAL;

	for (i = 0; i < FTRFS_RS_PARITY; i++)
		par[i] = parity[i];

	nerr = decode_rs8(ftrfs_rs_ctrl, data, par, FTRFS_SUBBLOCK_DATA,
			  NULL, 0, NULL, 0, NULL);

	if (nerr < 0) {
		pr_err_ratelimited("ftrfs: RS block uncorrectable\n");
		return -EBADMSG;
	}

	/* data[] already corrected in place by decode_rs8 if nerr > 0 */
	return 0;
}

/*
 * ftrfs_crc32 — compute CRC32 checksum
 * @buf: data buffer
 * @len: length in bytes
 *
 * Uses the kernel's hardware-accelerated crc32_le (same as ext4/btrfs).
 * Seed 0xFFFFFFFF, final XOR 0xFFFFFFFF (standard CRC-32/ISO-HDLC).
 */
__u32 ftrfs_crc32(const void *buf, size_t len)
{
	return crc32_le(0xFFFFFFFF, buf, len) ^ 0xFFFFFFFF;
}

/*
 * ftrfs_crc32_sb — compute CRC32 over the meaningful superblock fields
 *
 * Covers [0, offsetof(s_crc32)) and [offsetof(s_uuid), offsetof(s_pad)).
 * This includes the RS journal but excludes s_crc32 itself and s_pad.
 * Uses crc32_le() chaining so no temporary buffer is needed.
 *
 * Compared to the original design which only covered the first 64 bytes,
 * this detects corruption or tampering in the RS Radiation Event Journal.
 */
__u32 ftrfs_crc32_sb(const struct ftrfs_super_block *fsb)
{
	__u32 crc;
	const __u8 *base = (const __u8 *)fsb;

	/*
	 * crc32_le(seed, buf, len): seed and return value are both the raw
	 * internal CRC state (NOT XOR-finalized). Chain directly by passing
	 * the result of part 1 as seed for part 2.
	 *
	 * Part 1: [0, offsetof(s_crc32)) = 64 bytes
	 */
	crc = crc32_le(0xFFFFFFFF, base,
		       offsetof(struct ftrfs_super_block, s_crc32));

	/* Part 2: [offsetof(s_uuid), offsetof(s_pad)) = 1585 bytes */
	crc = crc32_le(crc,
		       base + offsetof(struct ftrfs_super_block, s_uuid),
		       offsetof(struct ftrfs_super_block, s_pad) -
		       offsetof(struct ftrfs_super_block, s_uuid));

	/* Final XOR to produce standard CRC-32/ISO-HDLC output */
	return crc ^ 0xFFFFFFFF;
}

