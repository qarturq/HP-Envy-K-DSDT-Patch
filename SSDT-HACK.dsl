// Instead of providing patched DSDT/SSDT, just include a single SSDT
// and do the rest of the work in config.plist

// A bit experimental, and a bit more difficult with laptops, but
// still possible.

// Note: No solution for missing IAOE here, but so far, not a problem.

DefinitionBlock("", "SSDT", 2, "hack", "_HACK", 0)
{
    External(_SB.PCI0, DeviceObj)
    External(_SB.PCI0.LPCB, DeviceObj)

    // All _OSI calls in DSDT are routed to XOSI...
    // XOSI simulates "Windows 2012" (which is Windows 8)
    // Note: According to ACPI spec, _OSI("Windows") must also return true
    //  Also, it should return true for all previous versions of Windows.
    Method(XOSI, 1)
    {
        // simulation targets
        // source: (google 'Microsoft Windows _OSI')
        //  http://download.microsoft.com/download/7/E/7/7E7662CF-CBEA-470B-A97E-CE7CE0D98DC2/WinACPI_OSI.docx
        Store(Package()
        {
            "Windows",              // generic Windows query
            "Windows 2001",         // Windows XP
            "Windows 2001 SP2",     // Windows XP SP2
            //"Windows 2001.1",     // Windows Server 2003
            //"Windows 2001.1 SP1", // Windows Server 2003 SP1
            "Windows 2006",         // Windows Vista
            "Windows 2006 SP1",     // Windows Vista SP1
            //"Windows 2006.1",     // Windows Server 2008
            "Windows 2009",         // Windows 7/Windows Server 2008 R2
            "Windows 2012",         // Windows 8/Windows Server 2012
            //"Windows 2013",       // Windows 8.1/Windows Server 2012 R2
            //"Windows 2015",       // Windows 10/Windows Server TP
        }, Local0)
        Return (Ones != Match(Local0, MEQ, Arg0, MTR, 0, 0))
    }

//
// ACPISensors configuration (ACPISensors.kext is not installed by default)
//

    // Not implemented for the Haswell Envy

//
// USB related
//

    // In DSDT, native GPRW is renamed to XPRW with Clover binpatch.
    // As a result, calls to GPRW land here.
    // The purpose of this implementation is to avoid "instant wake"
    // by returning 0 in the second position (sleep state supported)
    // of the return package.
    Method(GPRW, 2)
    {
        If (0x0d == Arg0) { Return(Package() { 0x0d, 0 }) }
        If (0x6d == Arg0) { Return(Package() { 0x6d, 0 }) }
        External(\XPRW, MethodObj)
        Return(XPRW(Arg0, Arg1))
    }

    // XWAK causes issues on wake from sleep (for some models), so it is disabled
    // by renaming to XXAK in DSDT (via config.plist) and overriden here to do nothing.
    //External(_SB.PCI0.XHC.XXAK, MethodObj)
    Method(_SB.PCI0.XHC.XWAK, 0, NotSerialized)
    {
        // nothing
    }

#ifdef ENVY_K1
    #include "SSDT-USB-K1.dsl"
#endif
#ifdef ENVY_K2
    #include "SSDT-USB-K2.dsl"
#endif

//
// For disabling the discrete GPU
//

    External(_SB.PCI0.PEG0.PEGP._OFF, MethodObj)
    External(_SB.PCI0.RP05.PEGP._OFF, MethodObj)
    Device(RMD2)
    {
        Name(_HID, "RMD20000")
        Method(_INI)
        {
            // disable discrete graphics (Nvidia/Radeon) if it is present
            If (CondRefOf(\_SB.PCI0.PEG0.PEGP._OFF)) { \_SB.PCI0.PEG0.PEGP._OFF() }
            If (CondRefOf(\_SB.PCI0.RP05.PEGP._OFF)) { \_SB.PCI0.RP05.PEGP._OFF() }
        }
    }

//
// Display backlight implementation
//
// From SSDT-PNLF.dsl
// Adding PNLF device for IntelBacklight.kext or AppleBacklight.kext+AppleBacklightInjector.kext

#define SANDYIVY_PWMMAX 0x710
#define HASWELL_PWMMAX 0xad9
#define SKYLAKE_PWMMAX 0x56c

    External(RMCF.BKLT, IntObj)
    External(RMCF.LMAX, IntObj)

    External(_SB.PCI0.IGPU, DeviceObj)
    Scope(_SB.PCI0.IGPU)
    {
        // need the device-id from PCI_config to inject correct properties
        OperationRegion(IGD5, PCI_Config, 0, 0x14)
    }

    // For backlight control
    Device(_SB.PCI0.IGPU.PNLF)
    {
        Name(_ADR, Zero)
        Name(_HID, EisaId ("APP0002"))
        Name(_CID, "backlight")
        // _UID is set depending on PWMMax
        // 14: Sandy/Ivy 0x710
        // 15: Haswell/Broadwell 0xad9
        // 16: Skylake/KabyLake 0x56c (and some Haswell, example 0xa2e0008)
        // 99: Other
        Name(_UID, 0)
        Name(_STA, 0x0B)

        // IntelBacklight.kext configuration
        Name(RMCF, Package()
        {
            "PWMMax", 0,
        })

        Field(^IGD5, AnyAcc, NoLock, Preserve)
        {
            Offset(0x02), GDID,16,
            Offset(0x10), BAR1,32,
        }

        OperationRegion(RMB1, SystemMemory, BAR1 & ~0xF, 0xe1184)
        Field(RMB1, AnyAcc, Lock, Preserve)
        {
            Offset(0x48250),
            LEV2, 32,
            LEVL, 32,
            Offset(0x70040),
            P0BL, 32,
            Offset(0xc8250),
            LEVW, 32,
            LEVX, 32,
            Offset(0xe1180),
            PCHL, 32,
        }

        Method(_INI)
        {
            // IntelBacklight.kext takes care of this at load time...
            // If RMCF.BKLT does not exist, it is assumed you want to use AppleBacklight.kext...
            If (CondRefOf(\RMCF.BKLT)) { If (1 != \RMCF.BKLT) { Return } }

            // Adjustment required when using AppleBacklight.kext
            Local0 = GDID
            Local2 = Ones
            if (CondRefOf(\RMCF.LMAX)) { Local2 = \RMCF.LMAX }

            If (Ones != Match(Package()
            {
                // Sandy
                0x0116, 0x0126, 0x0112, 0x0122,
                // Ivy
                0x0166, 0x016a,
                // Arrandale
                0x42, 0x46
            }, MEQ, Local0, MTR, 0, 0))
            {
                // Sandy/Ivy
                if (Ones == Local2) { Local2 = SANDYIVY_PWMMAX }

                // change/scale only if different than current...
                Local1 = LEVX >> 16
                If (!Local1) { Local1 = Local2 }
                If (Local2 != Local1)
                {
                    // set new backlight PWMMax but retain current backlight level by scaling
                    Local0 = (LEVL * Local2) / Local1
                    //REVIEW: wait for vblank before setting new PWM config
                    //For (Local7 = P0BL, P0BL == Local7, ) { }
                    Local3 = Local2 << 16
                    If (Local2 > Local1)
                    {
                        // PWMMax is getting larger... store new PWMMax first
                        LEVX = Local3
                        LEVL = Local0
                    }
                    Else
                    {
                        // otherwise, store new brightness level, followed by new PWMMax
                        LEVL = Local0
                        LEVX = Local3
                    }
                }
            }
            Else
            {
                // otherwise... Assume Haswell/Broadwell/Skylake
                if (Ones == Local2)
                {
                    // check Haswell and Broadwell, as they are both 0xad9 (for most common ig-platform-id values)
                    If (Ones != Match(Package()
                    {
                        // Haswell
                        0x0d26, 0x0a26, 0x0d22, 0x0412, 0x0416, 0x0a16, 0x0a1e, 0x0a1e, 0x0a2e, 0x041e, 0x041a,
                        // Broadwell
                        0x0BD1, 0x0BD2, 0x0BD3, 0x1606, 0x160e, 0x1616, 0x161e, 0x1626, 0x1622, 0x1612, 0x162b,
                    }, MEQ, Local0, MTR, 0, 0))
                    {
                        Local2 = HASWELL_PWMMAX
                    }
                    Else
                    {
                        // assume Skylake/KabyLake, both 0x56c
                        // 0x1916, 0x191E, 0x1926, 0x1927, 0x1912, 0x1932, 0x1902, 0x1917, 0x191b,
                        // 0x5916, 0x5912, 0x591b, others...
                        Local2 = SKYLAKE_PWMMAX
                    }
                }

                // This 0xC value comes from looking what OS X initializes this\n
                // register to after display sleep (using ACPIDebug/ACPIPoller)\n
                LEVW = 0xC0000000

                // change/scale only if different than current...
                Local1 = LEVX >> 16
                If (!Local1) { Local1 = Local2 }
                If (Local2 != Local1)
                {
                    // set new backlight PWMAX but retain current backlight level by scaling
                    Local0 = (((LEVX & 0xFFFF) * Local2) / Local1) | (Local2 << 16)
                    //REVIEW: wait for vblank before setting new PWM config
                    //For (Local7 = P0BL, P0BL == Local7, ) { }
                    LEVX = Local0
                }
            }

            // Now Local2 is the new PWMMax, set _UID accordingly
            // The _UID selects the correct entry in AppleBacklightInjector.kext
            If (Local2 == SANDYIVY_PWMMAX) { _UID = 14 }
            ElseIf (Local2 == HASWELL_PWMMAX) { _UID = 15 }
            ElseIf (Local2 == SKYLAKE_PWMMAX) { _UID = 16 }
            Else { _UID = 99 }
        }
    }


//
// Standard Injections/Fixes
//

    Scope(_SB.PCI0)
    {
        Device(IMEI)
        {
            Name (_ADR, 0x00160000)
        }

        Device(SBUS.BUS0)
        {
            Name(_CID, "smbus")
            Name(_ADR, Zero)
            Device(DVL0)
            {
                Name(_ADR, 0x57)
                Name(_CID, "diagsvault")
                Method(_DSM, 4)
                {
                    If (!Arg2) { Return (Buffer() { 0x03 } ) }
                    Return (Package() { "address", 0x57 })
                }
            }
        }

        External(IGPU, DeviceObj)
        Scope(IGPU)
        {
            // need the device-id from PCI_config to inject correct properties
            OperationRegion(RMIG, PCI_Config, 2, 2)
            Field(RMIG, AnyAcc, NoLock, Preserve)
            {
                GDID,16
            }

            // inject properties for integrated graphics on IGPU
            Method(_DSM, 4)
            {
                If (!Arg2) { Return (Buffer() { 0x03 } ) }
                Local1 = Package()
                {
                    "model", Buffer() { "place holder" },
                    "device-id", Buffer() { 0x12, 0x04, 0x00, 0x00 },
                    "hda-gfx", Buffer() { "onboard-1" },
                    "AAPL,ig-platform-id", Buffer() { 0x06, 0x00, 0x26, 0x0a },
                }
                Local0 = GDID
                If (0x0a16 == Local0) { Local1[1] = Buffer() { "Intel HD Graphics 4400" } }
                ElseIf (0x0416 == Local0) { Local1[1] = Buffer() { "Intel HD Graphics 4600" } }
                ElseIf (0x0a1e == Local0) { Local1[1] = Buffer() { "Intel HD Graphics 4200" } }
                Else
                {
                    // others (HD5000 and Iris) are natively supported
                    Local1 = Package()
                    {
                        "hda-gfx", Buffer() { "onboard-1" },
                        "AAPL,ig-platform-id", Buffer() { 0x06, 0x00, 0x26, 0x0a },
                    }
                }
                Return(Local1)
            }
        }
    }

//
// Fix SATA in RAID mode
//

    External(_SB.PCI0.SAT0, DeviceObj)
    Scope(_SB.PCI0.SAT0)
    {
        OperationRegion(SAT4, PCI_Config, 2, 2)
        Field(SAT4, AnyAcc, NoLock, Preserve)
        {
            SDID,16
        }
        Method(_DSM, 4)
        {
            If (!Arg2) { Return (Buffer() { 0x03 } ) }
            If (0x282a == SDID)
            {
                // 8086:282a is RAID mode, remap to supported 8086:2829
                Return (Package()
                {
                    "device-id", Buffer() { 0x29, 0x28, 0, 0 },
                })
            }
            Return (Package() { })
        }
    }

//
// Keyboard/Trackpad
//

    External(_SB.PCI0.LPCB.PS2K, DeviceObj)
    Scope (_SB.PCI0.LPCB.PS2K)
    {
        // Select specific keyboard map in VoodooPS2Keyboard.kext
        Method(_DSM, 4)
        {
            If (!Arg2) { Return (Buffer() { 0x03 } ) }
            Return (Package()
            {
                "RM,oem-id", "HPQOEM",
                "RM,oem-table-id", "Haswell-Envy-RMCF",
            })
        }

        // overrides for VoodooPS2 configuration... (much more could be done here)
        Name(RMCF, Package()
        {
            "Sentelic FSP", Package()
            {
                "DisableDevice", ">y",
            },
            "ALPS GlidePoint", Package()
            {
                "DisableDevice", ">y",
            },
            "Mouse", Package()
            {
                "DisableDevice", ">y",
            },
            "Keyboard", Package()
            {
                "Custom PS2 Map", Package()
                {
                    Package() { },
                    "e045=e037",
                    "e0ab=0",   // bogus Fn+F2/F3
                },
                "Custom ADB Map", Package()
                {
                    Package() { },
                    "e019=42",  // next track
                    "e010=4d",  // previous track
                },
            },
            "Synaptics TouchPad", Package()
            {
                "DynamicEWMode", ">y",
            },
        })
    }

    External(_SB.PCI0.LPCB.EC, DeviceObj)
    Scope(_SB.PCI0.LPCB.EC)
    {
        // The native _Qxx methods in DSDT are renamed XQxx,
        // so notifications from the EC driver will land here.

        // _Q10/Q11 called on brightness down/up
        Method (_Q10, 0, NotSerialized)
        {
            // Brightness Down
            Notify(\_SB.PCI0.LPCB.PS2K, 0x0405)
        }
        Method (_Q11, 0, NotSerialized)
        {
            // Brightness Up
            Notify(\_SB.PCI0.LPCB.PS2K, 0x0406)
        }
    }

//
// Battery Status (based on patching native DSDT with "HP G6 2221ss")
//

    // Override for ACPIBatteryManager.kext
    External(_SB.BAT0, DeviceObj)
    Name(_SB.BAT0.RMCF, Package()
    {
        "StartupDelay", 10,
    })

    Scope(_SB.PCI0.LPCB.EC)
    {
        // This is an override for battery methods that access EC fields
        // larger than 8-bit.

        OperationRegion (RMEC, EmbeddedControl, Zero, 0xFF)
        Field (RMEC, ByteAcc, Lock, Preserve)
        {
            Offset (0x04), 
            SMWX,8,SMWY,8,
            //...
            Offset (0x70),
            ADC0,8,ADC1,8,
            FCC0,8,FCC1,8,
            //...
            Offset (0x82),
            /*MBST*/,   8,
            CUR0,8,CUR1,8,
            BRM0,8,BRM1,8,
            BCV0,8,BCV1,8,
        }

        // SMD0, 256 bits, offset 4
        // FLD0, 64 bits, offset 4
        // FLD1, 128 bits, offset 4
        // FLD2, 198 bits, offset 4
        // FLD3, 256 bits, offset 4

        Method (RSMD, 0, NotSerialized) { Return(RECB(4,256)) }
        Method (WSMD, 1, NotSerialized) { WECB(4,256,Arg0) }
        Method (RFL3, 0, NotSerialized) { Return(RECB(4,256)) }
        Method (RFL2, 0, NotSerialized) { Return(RECB(4,198)) }
        Method (RFL1, 0, NotSerialized) { Return(RECB(4,128)) }
        Method (RFL0, 0, NotSerialized) { Return(RECB(4,64)) }

    // Battery utility methods

        Method (\B1B2, 2, NotSerialized) { Return (Or (Arg0, ShiftLeft (Arg1, 8))) }

        Method (WE1B, 2, Serialized)
        {
            OperationRegion(ERAM, EmbeddedControl, Arg0, 1)
            Field(ERAM, ByteAcc, NoLock, Preserve) { BYTE, 8 }
            Store(Arg1, BYTE)
        }
        Method (WECB, 3, Serialized)
        // Arg0 - offset in bytes from zero-based EC
        // Arg1 - size of buffer in bits
        // Arg2 - value to write
        {
            ShiftRight(Arg1, 3, Arg1)
            Name(TEMP, Buffer(Arg1) { })
            Store(Arg2, TEMP)
            Add(Arg0, Arg1, Arg1)
            Store(0, Local0)
            While (LLess(Arg0, Arg1))
            {
                WE1B(Arg0, DerefOf(Index(TEMP, Local0)))
                Increment(Arg0)
                Increment(Local0)
            }
        }
        Method (RE1B, 1, Serialized)
        {
            OperationRegion(ERAM, EmbeddedControl, Arg0, 1)
            Field(ERAM, ByteAcc, NoLock, Preserve) { BYTE, 8 }
            Return(BYTE)
        }
        Method (RECB, 2, Serialized)
        // Arg0 - offset in bytes from zero-based EC
        // Arg1 - size of buffer in bits
        {
            ShiftRight(Arg1, 3, Arg1)
            Name(TEMP, Buffer(Arg1) { })
            Add(Arg0, Arg1, Arg1)
            Store(0, Local0)
            While (LLess(Arg0, Arg1))
            {
                Store(RE1B(Arg0), Index(TEMP, Local0))
                Increment(Arg0)
                Increment(Local0)
            }
            Return(TEMP)
        }

    // Replaced battery methods
    
        External(ECOK, IntObj)
        External(MUT0, MutexObj)
        External(SMST, FieldUnitObj)
        External(SMCM, FieldUnitObj)
        External(SMAD, FieldUnitObj)
        External(SMPR, FieldUnitObj)
        External(SMB0, FieldUnitObj)
        
        External(BCNT, FieldUnitObj)
        External(\_SB.GBFE, MethodObj)
        External(\_SB.PBFE, MethodObj)
        External(\_SB.BAT0.PBIF, PkgObj)
        External(\SMA4, FieldUnitObj)
        External(\_SB.BAT0.FABL, IntObj)
        External(MBNH, FieldUnitObj)
        External(BVLB, FieldUnitObj)
        External(BVHB, FieldUnitObj)
        External(\_SB.BAT0.UPUM, MethodObj)
        External(\_SB.BAT0.PBST, PkgObj)
        External(SW2S, FieldUnitObj)
        External(BACR, FieldUnitObj)
        External(MBST, FieldUnitObj)
        External(\_SB.BAT0._STA, MethodObj)
        
        Method (SMRD, 4, NotSerialized)
        {
            If (LNot (ECOK))
            {
                Return (0xFF)
            }

            If (LNotEqual (Arg0, 0x07))
            {
                If (LNotEqual (Arg0, 0x09))
                {
                    If (LNotEqual (Arg0, 0x0B))
                    {
                        If (LNotEqual (Arg0, 0x47))
                        {
                            If (LNotEqual (Arg0, 0xC7))
                            {
                                Return (0x19)
                            }
                        }
                    }
                }
            }

            Acquire (MUT0, 0xFFFF)
            Store (0x04, Local0)
            While (LGreater (Local0, One))
            {
                And (SMST, 0x40, SMST)
                Store (Arg2, SMCM)
                Store (Arg1, SMAD)
                Store (Arg0, SMPR)
                Store (Zero, Local3)
                While (LNot (And (SMST, 0xBF, Local1)))
                {
                    Sleep (0x02)
                    Increment (Local3)
                    If (LEqual (Local3, 0x32))
                    {
                        And (SMST, 0x40, SMST)
                        Store (Arg2, SMCM)
                        Store (Arg1, SMAD)
                        Store (Arg0, SMPR)
                        Store (Zero, Local3)
                    }
                }

                If (LEqual (Local1, 0x80))
                {
                    Store (Zero, Local0)
                }
                Else
                {
                    Decrement (Local0)
                }
            }

            If (Local0)
            {
                Store (And (Local1, 0x1F), Local0)
            }
            Else
            {
                If (LEqual (Arg0, 0x07))
                {
                    Store (SMB0, Arg3)
                }

                If (LEqual (Arg0, 0x47))
                {
                    Store (SMB0, Arg3)
                }

                If (LEqual (Arg0, 0xC7))
                {
                    Store (SMB0, Arg3)
                }

                If (LEqual (Arg0, 0x09))
                {
                    Store (B1B2(SMWX,SMWY), Arg3)
                }

                If (LEqual (Arg0, 0x0B))
                {
                    Store (BCNT, Local3)
                    ShiftRight (0x0100, 0x03, Local2)
                    If (LGreater (Local3, Local2))
                    {
                        Store (Local2, Local3)
                    }

                    If (LLess (Local3, 0x09))
                    {
                        Store (RFL0(), Local2)
                    }
                    Else
                    {
                        If (LLess (Local3, 0x11))
                        {
                            Store (RFL1(), Local2)
                        }
                        Else
                        {
                            If (LLess (Local3, 0x19))
                            {
                                Store (RFL2(), Local2)
                            }
                            Else
                            {
                                Store (RFL3(), Local2)
                            }
                        }
                    }

                    Increment (Local3)
                    Store (Buffer (Local3) {}, Local4)
                    Decrement (Local3)
                    Store (Zero, Local5)
                    While (LGreater (Local3, Local5))
                    {
                        GBFE (Local2, Local5, RefOf (Local6))
                        PBFE (Local4, Local5, Local6)
                        Increment (Local5)
                    }

                    PBFE (Local4, Local5, Zero)
                    Store (Local4, Arg3)
                }
            }

            Release (MUT0)
            Return (Local0)
        }

        Method (SMWR, 4, NotSerialized)
        {
            If (LNot (ECOK))
            {
                Return (0xFF)
            }

            If (LNotEqual (Arg0, 0x06))
            {
                If (LNotEqual (Arg0, 0x08))
                {
                    If (LNotEqual (Arg0, 0x0A))
                    {
                        If (LNotEqual (Arg0, 0x46))
                        {
                            If (LNotEqual (Arg0, 0xC6))
                            {
                                Return (0x19)
                            }
                        }
                    }
                }
            }

            Acquire (MUT0, 0xFFFF)
            Store (0x04, Local0)
            While (LGreater (Local0, One))
            {
                If (LEqual (Arg0, 0x06))
                {
                    Store (Arg3, SMB0)
                }

                If (LEqual (Arg0, 0x46))
                {
                    Store (Arg3, SMB0)
                }

                If (LEqual (Arg0, 0xC6))
                {
                    Store (Arg3, SMB0)
                }

                If (LEqual (Arg0, 0x08))
                {
                    // Store(Arg3, SMW0)
                    Store(Arg3, SMWX) Store(ShiftRight(Arg3, 8), SMWY)
                }

                If (LEqual (Arg0, 0x0A))
                {
                    WSMD(Arg3)
                }

                And (SMST, 0x40, SMST)
                Store (Arg2, SMCM)
                Store (Arg1, SMAD)
                Store (Arg0, SMPR)
                Store (Zero, Local3)
                While (LNot (And (SMST, 0xBF, Local1)))
                {
                    Sleep (0x02)
                    Increment (Local3)
                    If (LEqual (Local3, 0x32))
                    {
                        And (SMST, 0x40, SMST)
                        Store (Arg2, SMCM)
                        Store (Arg1, SMAD)
                        Store (Arg0, SMPR)
                        Store (Zero, Local3)
                    }
                }

                If (LEqual (Local1, 0x80))
                {
                    Store (Zero, Local0)
                }
                Else
                {
                    Decrement (Local0)
                }
            }

            If (Local0)
            {
                Store (And (Local1, 0x1F), Local0)
            }

            Release (MUT0)
            Return (Local0)
        }
    }

    Scope (_SB.BAT0)
    {
        Method (UPBI, 0, NotSerialized)
        {
            Store (B1B2(^^PCI0.LPCB.EC.FCC0,^^PCI0.LPCB.EC.FCC1), Local5)
            If (LAnd (Local5, LNot (And (Local5, 0x8000))))
            {
                ShiftRight (Local5, 0x05, Local5)
                ShiftLeft (Local5, 0x05, Local5)
                Store (Local5, Index (PBIF, One))
                Store (Local5, Index (PBIF, 0x02))
                Divide (Local5, 0x64, , Local2)
                Add (Local2, One, Local2)
                If (LLess (B1B2(^^PCI0.LPCB.EC.ADC0,^^PCI0.LPCB.EC.ADC1), 0x0C80))
                {
                    Multiply (Local2, 0x0E, Local4)
                    Add (Local4, 0x02, Index (PBIF, 0x05))
                    Multiply (Local2, 0x09, Local4)
                    Add (Local4, 0x02, Index (PBIF, 0x06))
                    Multiply (Local2, 0x0B, Local4)
                }
                Else
                {
                    If (LEqual (SMA4, One))
                    {
                        Multiply (Local2, 0x0C, Local4)
                        Add (Local4, 0x02, Index (PBIF, 0x05))
                        Multiply (Local2, 0x07, Local4)
                        Add (Local4, 0x02, Index (PBIF, 0x06))
                        Multiply (Local2, 0x09, Local4)
                    }
                    Else
                    {
                        Multiply (Local2, 0x0A, Local4)
                        Add (Local4, 0x02, Index (PBIF, 0x05))
                        Multiply (Local2, 0x05, Local4)
                        Add (Local4, 0x02, Index (PBIF, 0x06))
                        Multiply (Local2, 0x07, Local4)
                    }
                }

                Add (Local4, 0x02, FABL)
            }

            If (^^PCI0.LPCB.EC.MBNH)
            {
                Store (^^PCI0.LPCB.EC.BVLB, Local0)
                Store (^^PCI0.LPCB.EC.BVHB, Local1)
                ShiftLeft (Local1, 0x08, Local1)
                Or (Local0, Local1, Local0)
                Store (Local0, Index (PBIF, 0x04))
                Store ("OANI$", Index (PBIF, 0x09))
                Store ("NiMH", Index (PBIF, 0x0B))
            }
            Else
            {
                Store (^^PCI0.LPCB.EC.BVLB, Local0)
                Store (^^PCI0.LPCB.EC.BVHB, Local1)
                ShiftLeft (Local1, 0x08, Local1)
                Or (Local0, Local1, Local0)
                Store (Local0, Index (PBIF, 0x04))
                Sleep (0x32)
                Store ("LION", Index (PBIF, 0x0B))
            }

            Store ("Primary", Index (PBIF, 0x09))
            UPUM ()
            Store (One, Index (PBIF, Zero))
        }
        Method (UPBS, 0, NotSerialized)
        {
            Store (B1B2(^^PCI0.LPCB.EC.CUR0,^^PCI0.LPCB.EC.CUR1), Local0)
            If (And (Local0, 0x8000))
            {
                If (LEqual (Local0, 0xFFFF))
                {
                    Store (Ones, Index (PBST, One))
                }
                Else
                {
                    Not (Local0, Local1)
                    Increment (Local1)
                    And (Local1, 0xFFFF, Local3)
                    Store (Local3, Index (PBST, One))
                }
            }
            Else
            {
                Store (Local0, Index (PBST, One))
            }

            Store (B1B2(^^PCI0.LPCB.EC.BRM0,^^PCI0.LPCB.EC.BRM1), Local5)
            If (LNot (And (Local5, 0x8000)))
            {
                ShiftRight (Local5, 0x05, Local5)
                ShiftLeft (Local5, 0x05, Local5)
                If (LNotEqual (Local5, DerefOf (Index (PBST, 0x02))))
                {
                    Store (Local5, Index (PBST, 0x02))
                }
            }

            If (LAnd (LNot (^^PCI0.LPCB.EC.SW2S), LEqual (^^PCI0.LPCB.EC.BACR, One)))
            {
                Store (FABL, Index (PBST, 0x02))
            }

            Store (B1B2(^^PCI0.LPCB.EC.BCV0,^^PCI0.LPCB.EC.BCV1), Index (PBST, 0x03))
            Store (^^PCI0.LPCB.EC.MBST, Index (PBST, Zero))
        }
    }

    Method (\_SB.PCI0.ACEL.CLRI, 0, Serialized)
    {
        Store (Zero, Local0)
        If (LEqual (^^LPCB.EC.ECOK, One))
        {
            If (LEqual (^^LPCB.EC.SW2S, Zero))
            {
                If (LEqual (^^^BAT0._STA (), 0x1F))
                {
                    If (LLessEqual (B1B2(^^LPCB.EC.BRM0,^^LPCB.EC.BRM1), 0x96))
                    {
                        Store (One, Local0)
                    }
                }
            }
        }
        Return (Local0)
    }
}

