/**********************************
    loongson3_ddr2_config.S
        used to set up ddr controllers MC0 and MC1
        and set up the memory space on L2 Xbar
    input: s1--MC1 & MC0 DIMM info and Node ID
    note: s1 is damaged by the end of this file
    original: whd
    rewrite by cxk on 11/11/2010
    1: reorder the program
    2: DIMM info and memory size is set according to s1[MC1&0_MEMSIZE]
    note: config L2 Xbar still need to be finished,currently only support limited MEMSIZE.
    v1.0    raw
    v1.2    add support for 4G memsize per MC, modify the L2-Xbar config manner of MC1
            to reduce code size.
    v1.4    Modify L2 Xbar config reg code at Interleave mode to reduce code size
            new code:
            1. according to Memsize config open space
            2. config interleave bits
    v1.6    Modify for 3B which only has 1 MC(MC0).
    v1.8    Modify L2 Xbar configure manner for new pmon-kernel interface.
                ---high address always starts from 0x80000000.
************************************/

#######################################################
/**************************
0. s1 reset code
**************************/
#ifdef  AUTO_DDR_CONFIG
    bal     PROBE_NODE_DIMM
    nop
#endif

#ifdef  PRINT_MSG
    /* show value of s1 */
    PRINTSTR("\r\n\r\ns1 = 0x");
    dsrl    a0, s1, 32
    bal     hexserial
    nop
    PRINTSTR("__")
    move    a0, s1
    bal     hexserial
    nop
    PRINTSTR("\r\n")
#endif

#if 0   //def  AUTO_DDR_CONFIG     //hot fix for board misconnection--temp code
    GET_ROW_SIZE
    dli     a0, 0x2
    bne     a1, a0, 1f
    nop
    //a1 == 2, row num is 14, decrease one(!!!a1+1), half the density
    daddu   a1, a1, 0x1
    dli     a0, 0x7
    dsll    a0, a0, ROW_SIZE_OFFSET
    not     a0, a0
    and     s1, s1, a0
    dsll    a1, a1, ROW_SIZE_OFFSET
    or      s1, s1, a1

    //half the density
    GET_MC0_MEMSIZE
    dsrl    a1, a1, 0x1
    dli     a0, MC_MEMSIZE_MASK
    dsll    a0, a0, MC0_MEMSIZE_OFFSET
    not     a0, a0
    and     s1, s1, a0
    dsll    a1, a1, MC0_MEMSIZE_OFFSET
    or      s1, s1, a1
1:
#if 1
    /* show value of s1 */
    PRINTSTR("\r\nnew s1 = 0x");
    dsrl    a0, s1, 32
    bal     hexserial
    nop
    PRINTSTR("__")
    move    a0, s1
    bal     hexserial
    nop
    PRINTSTR("\r\n")
#endif
#endif

#ifdef DEBUG_DDR_PARAM
    PRINTSTR("\r\nChange s1?:\r\n");
    dli     t6, 0x00
    bal     inputaddress    #input value stored in v0
    nop
    beqz    v0, 1f
    nop
    move    s1, v0
1:
#endif

/**************************
1. check NODE memory size.
  -------max size 64GB now
**************************/
    //MC0_ONLY
    GET_MC0_MEMSIZE
    beqz    a1, 89f
    nop
    dli     t5, 0x40
    bgt     a1, t5, 89f
    nop
#if 1
    PRINTSTR("\r\ns1 = 0x")
    move    a0, s1
    bal     hexserial
    nop
    PRINTSTR("\r\n")
#endif
/************************
2. set up Memory Controller.
************************/
/***********************
for single chip or multi-chip:
t0: X-bar config base
t2: chip configuration register location
t0,t2 shouldn't be changed to the end of this file.
**********************/
    GET_NODE_ID_a0
    dli     t2, 0x900000001fe00180
    dli     t0, 0x900000003ff00000
    or      t2, t2, a0
    or      t0, t0, a0
    //add 3B register location offset
    dsrl    a0, a0, 44
    dsll    a0, a0, 14
    daddu   t0, t0, a0
    //clear odd NODE_ID to even for chip config
    dli     a1, 0x1
    dsll    a1, a1, 44
    not     a1, a1
    and     t2, t2, a1

#if 1
    /* show system config register  */
    PRINTSTR("\r\nSys Configure reg = 0x");
    ld      t1, 0x0(t2) 
    dsrl    a0, t1, 32
    bal     hexserial
    nop
    move    a0, t1
    bal     hexserial
    nop
    PRINTSTR("\r\n")
#endif

#if 0   //necessary
    TTYDBG("Disable DDR buffer cpu\r\n")
    GET_NODE_ID_a1
    and     a1, a1, 0x1 //a1 == 0(even NODE) or 1(odd NODE)
    dsll    a2, a1, 2   //a2 == 0(even NODE) or 4(odd NODE)
    daddu   a1, a2, a1  //a1 == 0(even NODE) or 5(odd NODE)
    lw      a2, 0x0(t2)
    li      a0, 0x20    //bit[5]--MC0 DDR buffer cpu
    sll     a0, a0, a1  //sll 0 or 5
    not     a0, a0
    and     a2, a2, a0
    sw      a2, 0x0(t2)
#endif

    bal     mc_init
    nop
    PRINTSTR("\r\nMC0 Config DONE\r\n")
/*****************************
 3. set msize for this NODE
******************************/
//use MC0 only
    GET_MC0_MEMSIZE
    move    t5, a1
    GET_NODE_ID_a0;
    dsrl    a0, a0, 44  //because of the macro define
    dsll    a0, a0, 3   //a0=a0*8
    dsll    t5, t5, a0
    or      msize, msize, t5

#ifdef  PRINT_MSG
    PRINTSTR("\r\nmsize = 0x")
    move    a0, msize
    bal     hexserial
    nop
    PRINTSTR("\r\n")
#endif
/*******************************
 4. config L2 X-bar
    according to MC0_MEMSIZE bits in s1 decide memory size 
    note: currently, only support memory size: 512M, 1G, 2G, 3G, 4G, 8G;
*******************************/
    sync
    nop
    nop
    nop
    nop

    //disable default pci window
    L2XBAR_DISABLE_WINDOW(0x100);
/*MC0_ONLY */
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x10, \
                    0x0000000000000000, \
                    0xFFFFFFFFF0000000, \
                    0x00000000000000F0)
    PRINTSTR("MC0 space open : 0x00000000 - 0x0FFFFFFF\r\n")
    //Config PCI windows
    L2XBAR_CONFIG_PCI_AS_CPU(0x10);
    L2XBAR_CONFIG_PCI_BASE_0to8(0x110);
    PRINTSTR("PCI space open: 0x80000000 - 0x8FFFFFFF\r\n")

//config high memory windows
/*MC0_ONLY */
    GET_MC0_MEMSIZE
    dli     t5, 0x1
    beq     a1, t5, 1f
    nop
    dli     t5, 0x2
    beq     a1, t5, 2f
    nop
    dli     t5, 0x4
    beq     a1, t5, 4f
    nop
    dli     t5, 0x6
    beq     a1, t5, 6f
    nop
    dli     t5, 0x8
    beq     a1, t5, 8f
    nop
    dli     t5, 0x10
    beq     a1, t5, 10f
    nop
    dli     t5, 0x20
    //temp code, MEM size >= 16G, use 16G only
    bgeu    a1, t5, 20f
    nop
    b       89f  //error condition
    nop
1:     //ddr_512MB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFFE0000000, \
                    0x00000000000000F0)
    PRINTSTR("MC0 space open : 0x80000000 - 0x9FFFFFFF\r\n")
    b       81f
    nop
2:     //ddr_1GB_MC:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFFC0000000, \
                    0x00000000000000F0)
    PRINTSTR("MC0 space open : 0x80000000 - 0xBFFFFFFF\r\n")
    b       81f
    nop
4:     //ddr_2GB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000000000F0)
    PRINTSTR("MC0 space open : 0x80000000 - 0xFFFFFFFF\r\n")
    b       81f
    nop
6:     //ddr_3GB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000000000F0)
    XBAR_CONFIG_NODE_a0(0x28, \
                    0x0000000100000000, \
                    0xFFFFFFFFC0000000, \
                    0x00000000800000F0)
    PRINTSTR("MC0 space open : 0x080000000 - 0x13FFFFFFF\r\n")
    b       81f
    nop
8:     //ddr_4GB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000000000F0)
    XBAR_CONFIG_NODE_a0(0x28, \
                    0x0000000100000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000800000F0)
    PRINTSTR("MC0 space open : 0x080000000 - 0x17FFFFFFF\r\n")
    b       81f
    nop
10:     //ddr_8GB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000000000F0)
    XBAR_CONFIG_NODE_a0(0x28, \
                    0x0000000100000000, \
                    0xFFFFFFFF00000000, \
                    0x00000001000000F0)
    XBAR_CONFIG_NODE_a0(0x30, \
                    0x0000000200000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000800000F0)
    PRINTSTR("MC0 space open : 0x080000000 - 0x27FFFFFFF\r\n")
    b       81f
    nop
20:     //ddr_16GB_MC0:
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x20, \
                    0x0000000080000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000000000F0)
    XBAR_CONFIG_NODE_a0(0x28, \
                    0x0000000100000000, \
                    0xFFFFFFFF00000000, \
                    0x00000001000000F0)
    XBAR_CONFIG_NODE_a0(0x30, \
                    0x0000000200000000, \
                    0xFFFFFFFF00000000, \
                    0x00000002000000F0)
    XBAR_CONFIG_NODE_a0(0x38, \
                    0x0000000300000000, \
                    0xFFFFFFFF00000000, \
                    0x00000003000000F0)
    XBAR_CONFIG_NODE_a0(0x18, \
                    0x0000000400000000, \
                    0xFFFFFFFF80000000, \
                    0x00000000800000F0)
    PRINTSTR("MC0 space open : 0x080000000 - 0x47FFFFFFF\r\n")
    b       81f
    nop
81:
    //Config other PCI space exactly as cpu windows
    L2XBAR_CONFIG_PCI_AS_CPU(0x20);
    L2XBAR_CONFIG_PCI_AS_CPU(0x28);
    L2XBAR_CONFIG_PCI_AS_CPU(0x30);
    L2XBAR_CONFIG_PCI_AS_CPU(0x38);
    L2XBAR_CONFIG_PCI_AS_CPU(0x18);
    PRINTSTR("Full PCI space opened as cpu.\r\n")
    b       1f
    nop

89: //error: memory size not in support range
    PRINTSTR("The MEMSIZE is not supported, the L2-Xbar will not be configured!!!\r\n")
    PRINTSTR("-------------------------------------------\r\n")
#if 0
    GET_NODE_ID_a0;
    XBAR_CONFIG_NODE_a0(0x0, \
                0x0, \
                0x0, \
                0x0)
    PRINTSTR("!!!!!!!!!!MC space is disabled\r\n")
#endif
1:
    sync
    nop
    nop
    nop
    nop
