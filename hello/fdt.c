/*
 * Minimal flattened-device-tree (DTB) reader, freestanding (no libc, no OS).
 *
 * Purpose: at boot U-Boot hands us, in x0, the DTB it patched. Its Rockchip
 * display driver writes the *real* framebuffer address into the
 * `rockchip,drm-logo` reserved-memory node's `reg` (see README "Sources of
 * truth": chi-u-boot rockchip_display.c:1459, fdt_update_reserved_memory).
 * We walk the DTB and return that address, so nothing has to be hardcoded.
 *
 * DTB format (all multi-byte fields are big-endian):
 *   header: magic(0xd00dfeed), totalsize, off_dt_struct, off_dt_strings, ...
 *   struct block: a stream of 32-bit tokens:
 *       BEGIN_NODE(1) + name (NUL-term, 4-byte padded)
 *       END_NODE(2)
 *       PROP(3) + len(u32) + nameoff(u32) + value (len bytes, 4-byte padded)
 *       NOP(4), END(9)
 *   strings block: NUL-terminated property names, indexed by nameoff.
 */

#include <stdint.h>

#define FDT_MAGIC      0xd00dfeedu
#define FDT_BEGIN_NODE 0x1u
#define FDT_END_NODE   0x2u
#define FDT_PROP       0x3u
#define FDT_NOP        0x4u
#define FDT_END        0x9u

static uint32_t be32(const uint8_t *p)
{
	return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
	       ((uint32_t)p[2] << 8)  |  (uint32_t)p[3];
}

static int streq(const char *a, const char *b)
{
	while (*a && *a == *b) { a++; b++; }
	return *a == *b;
}

/* Does the byte range [v, v+len) contain the NUL-terminated needle? */
static int mem_contains(const uint8_t *v, uint32_t len, const char *needle)
{
	for (uint32_t i = 0; i < len; i++) {
		uint32_t j = 0;
		while (needle[j] && i + j < len && v[i + j] == (uint8_t)needle[j])
			j++;
		if (!needle[j])
			return 1;
	}
	return 0;
}

static uint32_t align4(uint32_t x) { return (x + 3u) & ~3u; }

/*
 * Find the `rockchip,drm-logo` node and return the base address from its `reg`.
 * The node lives under /reserved-memory, which uses #address-cells=2 and
 * #size-cells=2, so `reg` is <addr_hi addr_lo size_hi size_lo>. Returns 0 if
 * the node/reg isn't present (e.g. U-Boot didn't run the fixup on this path).
 */
uint64_t fdt_find_drm_logo(const void *dtb)
{
	const uint8_t *base = (const uint8_t *)dtb;
	if (be32(base) != FDT_MAGIC)
		return 0;

	uint32_t off_struct  = be32(base + 8);
	uint32_t off_strings = be32(base + 12);
	const uint8_t *strings = base + off_strings;

	uint32_t pos = off_struct;
	int cur_match = 0;          /* current node's compatible matches drm-logo */
	int have_reg  = 0;
	uint64_t reg_addr = 0;

	for (;;) {
		uint32_t tok = be32(base + pos);
		pos += 4;

		if (tok == FDT_BEGIN_NODE) {
			/* skip the NUL-terminated, 4-byte-padded node name */
			uint32_t s = pos;
			while (base[pos]) pos++;
			pos++;                    /* the NUL */
			pos = off_struct + align4(pos - off_struct);
			(void)s;
			/* entering a node: reset per-node state */
			cur_match = 0;
			have_reg  = 0;
			reg_addr  = 0;
		} else if (tok == FDT_END_NODE) {
			if (cur_match && have_reg)
				return reg_addr;      /* found it */
		} else if (tok == FDT_PROP) {
			uint32_t len     = be32(base + pos); pos += 4;
			uint32_t nameoff = be32(base + pos); pos += 4;
			const char *pname = (const char *)(strings + nameoff);
			const uint8_t *val = base + pos;
			pos += align4(len);

			if (streq(pname, "compatible")) {
				if (mem_contains(val, len, "rockchip,drm-logo"))
					cur_match = 1;
			} else if (streq(pname, "reg") && len >= 8) {
				reg_addr = ((uint64_t)be32(val) << 32) | be32(val + 4);
				have_reg = 1;
			}
		} else if (tok == FDT_NOP) {
			/* nothing */
		} else { /* FDT_END or anything unexpected */
			break;
		}
	}
	return 0;
}
