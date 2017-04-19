#!/usr/bin/env python
"""
 Describes a system used for performance testing.
 Produces a text display of the hardware found in the machine the script runs on.
 Output will look something like this:
 
 HP ProLiant DL380 G7
Memory: 270 GB used by kernel, 1 x 2 GB +17 x 16 GB = 274 GB @ 1333 MHz
2 x CPU X5660 @ 2.80GHz 6 cores each (24 Hyperthreads)
Operating system:
 Linux distribution: CentOS 6.6
 Kernel: 2.6.32-504.12.2.el6.x86_64
 Boot options: crashkernel=128M
 Red Hat transparent huge pages enabled and defrag enabled
 Virtual memory over-commit disabled

Logical drives on HP controllers:
P410 in Slot 4
 1: 279.4 GB OK /dev/sdi
 2: 279.4 GB OK /dev/sdj
 3: 279.4 GB OK /dev/sdk
 4: 279.4 GB OK /dev/sdl
 5: 279.4 GB OK /dev/sdm
 6: 279.4 GB OK /dev/sdn
 7: 279.4 GB OK /dev/sdo
 8: 279.4 GB OK /dev/sdp

P410i in Slot 0 (Embedded)
 1: 279.4 GB OK /dev/sda
 2: 279.4 GB OK /dev/sdb
 3: 279.4 GB OK /dev/sdc
 4: 279.4 GB OK /dev/sdd
 5: 279.4 GB OK /dev/sde
 6: 279.4 GB OK /dev/sdf
 7: 279.4 GB OK /dev/sdg
 8: 279.4 GB OK /dev/sdh

Physical drives:
  9 x HP EG0300FAWHV 300 GB 10K RPM
  6 x HP DG0300FARVV 300 GB 10K RPM
  1 x HP EG0300FBVFL 300 GB 10K RPM

Network interface controllers:
 2 x NetXen Incorporated NX3031 Multifunction 1/10-Gigabit Server Adapter (rev 42)
 4 x Broadcom NetXtreme II BCM5709 Gigabit Ethernet (rev 20)

HDFS block size 128 MB data threads 4096

"""

import os, subprocess

def sudo(arglist):
    """
    The sudo command fails when run without a tty, so get one.
    Returns the subprocess object.
    Might use the os.openpty function instead some day
    """

    cmdlist = ["sudo", "-n"]
    cmdlist.extend(arglist)
    cmd = ' '.join(cmdlist)
    return subprocess.Popen(["script", "-c", cmd, "-q", "/dev/null"],
                            stdin=open("/dev/null", 'r'),
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
def do_os():
    """
    The operating system basics
    """

    print "Operating system:"
    CMD = "/usr/sbin/lsb_release"
    REDHAT = "/etc/redhat-release"
    proc = None
    if os.path.exists(CMD):
        proc = subprocess.Popen([CMD, "--description"],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
        f_in = proc.stdout
    elif os.path.exists(REDHAT):
        # Fall back on the old way of reading a file
        f_in = open(REDHAT)
    else:
        f_in = None

    if f_in:
        words = f_in.read().split()
        f_in.close()
        for word in words:
            if word in ["Description:", "Server", "release"]:
                words.remove(word)
            elif word.startswith('('):
                # No reason for meaningless code names
                words.remove(word)
                if len(words):
                    print " Linux distribution:", ' '.join(words)
    if proc:
        proc.wait()

    proc = subprocess.Popen(["uname", "--kernel-release"],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    print " Kernel:", proc.stdout.read(),
    proc.wait()

    f_in = open("/proc/cmdline")
    words = f_in.read().split()
    f_in.close()
    options = []
    for word in words:
        if word in ["ro", "rhgb", "quiet"]:
            continue
        # Skip noisy options such as those for GUIs
        for noisy in ["root=", "ramdisk_size=",
                      "vga=", "usbcore.autosuspend=",
                      "rd_NO_", "rd_MD_",
                      "rd_LVM_",
                      "LANG=", "SYSFONT=",
                      "KEYBOARDTYPE=", "KEYTABLE="]:
            if word.startswith(noisy):
                word = ""
                break
        if len(word):
            options.append(word)

    if len(options):
        print " Boot options:", ' '.join(options)
    do_settings()
    print

def do_cpu():
    """
    Decode CPU number and Hyper-Threading setting
    """
    f_in = open("/proc/cpuinfo")
    threads = 0
    cores = 0
    physical = "0"
    cpus = set()
    packages = set()
    model = "Unknown"
    brand = "Intel"
    for line in f_in:
        words = line.split()
        if len(words) < 3:
            continue
        if words[0] == "processor":
            threads += 1
        elif len(words) < 4:
                continue
        if words[0:2] == ["model", "name"]:
            model = ""
            for modword in words[3:]:
                if modword in [ "Intel(R)",
                                "Xeon(R)",
                                "Processor"]:
                    continue
                if modword == "Opteron(tm)":
                    modword = "Opteron"
                elif modword == "AMD":
                    brand = "AMD"
                elif modword == "Core(TM)":
                    modword = "Core"
                elif modword == "0":
                    continue
                if len(model):
                    model += " "
                model += modword
        elif words[0:2] == ["cpu", "cores"]:
            if cores < int(words[3]):
                cores = int(words[3])
        elif words[0:2] == ["physical", "id"]:
            physical = words[3]
            packages.add(physical)
        elif words[0:2] == ["core", "id"]:
            cpus.add("%s %s" % (physical, words[3]))
    f_in.close()

    # Some kernels do not have "cpu cores"?
    # print "cores=%d cpus=%d" % (cores, len(cpus))
    chips = len(packages)
    if cores == 0:
        cores = len(cpus)
        if chips > 1:
            cores /= chips

    if chips == 0:
        # Amazon and other virtual machines
        print threads, "x", model, "(virtual)"
        return threads

    if chips > 1:
        print chips, "x", model,
    else:
        print model,

    if cores != 1:
        if chips > 1:
            print cores, "cores each",
        else:
            print cores, "cores",
    else:
        print "single-core",
    if brand == "Intel":
        if threads > cores*chips:
            print "(%d Hyperthreads)" % threads
        else:
            print "(Hyperthreading off)"
    else:
        print
    return cores*chips

def pretty_size_kb(value):
    """
    More human-readable value instead of zillions of digits
    """

    if value < 1024:
        return str(value) + " KB"
    if value < 1024 * 1024:
        return str(value/1024) + " MB"
    return str(value/(1024*1024)) + " GB"

def do_mem():
    """
    Memory size and settings
    Merge this into DMI decoded info
    """

    proc = sudo(["dmidecode"])
    mode = None
    system = ""
    speed = "Unknown"
    dimm = 0
    dimms = dict()

    for line in proc.stdout:
        words = line.split()
        if len(words) < 2:
            mode = None
            continue
        if words == ["System", "Information"]:
            mode = "system"
        if words == ["Memory", "Device"]:
            mode = "memory"
        elif mode == "system":
            if words[0] == "Manufacturer:":
                for word in words[1:]:
                    if word in ["Inc", "Inc."]:
                        continue
                    system += word
                    system += " "
            elif words[0:2] == ["Product", "Name:"]:
                system += ' '.join(words[2:])
                system += " "
        elif mode == "memory":
            if words[0:2] == ["Form", "Factor:"]:
                # SuperMicro systems have flash, but we only count DIMMS
                if words[2] not in["DIMM", "FB-DIMM"]:
                    mode = None
                else:
                    if dimm in dimms:
                        dimms[dimm] += 1
                    else:
                        dimms[dimm] = 1
            elif words[0] == "Speed:":
                speed = ' '.join(words[1:3])
            elif words[0] == "Size:":
                if words[1] == "No":
                    mode = None
                    continue
                if words[2] == "GB":
                    dimm = int(words[1])
                else:
                    dimm = int(words[1])/1024

    print system
    proc.stdout.close()
    proc.wait()

    f_in = open("/proc/meminfo")
    # should read more, such as Hugepage info?
    words = f_in.read().split()
    f_in.close()
    if words[0] == "MemTotal:":
        value = int(words[1])
        print "Memory:", pretty_size_kb(value), "used by kernel,",
    total = 0
    for size in sorted(dimms.keys()):
        if total > 0:
            plus = "+"
        else:
            plus = ""
        print "%s%d x %d GB" % (plus, dimms[size], size),
        total += dimms[size] * size
    if len(dimms):
        print "= %d GB" % total,
    else:
        print "(need sudo dmidecode for details)",
    if speed == "Unknown":
        print
    else:
        print "@", speed

def do_settings():
    """
    Some OS settings that might matter
    """
    def do_thp(path, variant):
        if not os.path.exists(path):
            return False
        enabled = "unknown"
        defrag = "unknown"
        try:
            words = open(path +"/enabled", 'r').read().split()
            if "[always]" in words:
                enabled = "enabled"
            else:
                enabled = "disabled"
            words = open(path +"/defrag", 'r').read().split()
            if "[always]" in words:
                defrag = "enabled"
            else:
                defrag = "disabled"
        except Exception as e:
            pass
        print " %s transparent huge pages %s and defrag %s" % (
                                    variant, enabled, defrag)
        return True

    defrag = "/sys/kernel/mm/redhat_transparent_hugepage"
    if not do_thp(defrag, "Red Hat"):
        do_thp(defrag.replace("redhat_", ""), "Modern Linux")
    over = open("/proc/sys/vm/overcommit_memory", 'r').read()
    if over[0] == '1':
        enabled = "enabled"
    elif over[0] == '2':
        enabled = "maybe"
    else:
        enabled = "disabled"
    print " Virtual memory over-commit", enabled


def print_drives(logicals):
    """
    Helper to format logical drives on a given controller
    """
    for drive in sorted(logicals.keys()):
        print " %s: %s" % (drive, logicals[drive])
    print

def do_lsi():
    """
    Do LSI controller specific reporting
    """

    def speed_of(model):
        """
        Guess the speed of drives from certain manufacturers
        """
        words = model.split()
        if words[0] in ["SEAGATE", "Seagate"]:
            if len(words) < 2:
                return ""
            if words[1].startswith("0MP0", 4):
                return "15K RPM 2.5 inch"
            if words[1].startswith("06", 6):
                return "7.2K RPM 2.5 inch"
            if words[1].startswith("0NC0", 5):
                return "7.2K RPM 3.5 inch"
            if (words[1].startswith("0NM0", 5) or
                words[1].startswith("ST3") or
                words[1].startswith("ST2")):
                return "7.2K RPM 3.5 inch"
            if words[1].startswith("ST4000NC"):
                return "5.9K RPM 3.5 inch"
            if "0NS" in words[1] and words[1].startswith("ST91"):
                return "7.2K RPM 2.5 inch SATA"
            if (words[1].startswith("ST9") or
                words[1].startswith("0MM0",4) or
                words[1].startswith("0MM0",5)):
                return "10K RPM 2.5 inch"

        if words[0] == "TOSHIBA":
            if words[1].startswith("MBF2"):
                return "10K RPM 2.5 inch"
            if words[1].startswith("MG03"):
                return "7.2K RPM 3.5 inch"

        if "ST910" in words[0]:
            return "7.2K RPM 2.5 inch SATA"

        return ""

    def parse_proc(proc, adapters, physical=False):
        """
        Helper to parse the odd output of MegCli
        """

        # state of the MegaCli parser, logical or physical
        if physical:
            mode = "physical"
        else:
            mode = None

        # map of "logical drives"
        logicals = dict()
        logical = 1
        chunk = 1
        raid = "0"

        # maps of physical drive properties
        counts = dict()
        sizes = dict()
        size = ""

        for line in proc.stdout:
            words = line.split()
            if len(words) < 1:
                continue

            if words[0] == "Adapter":
                if logicals:
                    # Print virtual drives on last adapter, if any
                    print_drives(logicals)
                    logicals = dict()
                if physical:
                    continue
                if words[1] in adapters:
                    print "Adapter", words[1], adapters[words[1]]
                else:
                    print "Adapter", words[1], "UNKNOWN?"
            elif words[0:2] == ["Virtual", "Drive:"]:
                mode = "logical"
                logical = int(words[2])
                logicals[logical] = ""
            elif words[0] == "PD:":
                mode = "physical"
            elif mode == "logical":
                if words[0:2] == ["Size", ":"]:
                    size = ' '.join(words[2:])
                    logicals[logical] += size + " "
                elif words[0:2] == ["State", ":"]:
                    logicals[logical] += ' '.join(words[2:]) + " "
                elif words[0:3] == ["Current", "Cache", "Policy:"]:
                    logicals[logical] += words[3].rstrip(',') + " "
                # Should parse out more RAID details for these
            elif mode == "physical":
                if words[0:2] == ["Raw", "Size:"]:
                    size = ' '.join(words[2:4])
                elif words[0:2] == ["Inquiry", "Data:"]:
                    model = ' '.join(words[2:4])
                    if "ST91000640NS" in model:
                        # Special-case the odd SATA disks
                        # They get serial number pre-pended?
                        words = model.split()
                        model = "Seagate " + words[0][8:]
                    if model in counts:
                        counts[model] += 1
                    else:
                        counts[model] = 1
                    sizes[model] = size

        proc.stdout.close()
        proc.wait()
        if logicals:
            print_drives(logicals)
        if len(counts) == 0:
            return False
        print "Physical drives:"
        for model in counts:
            print " ", counts[model], "x", model, sizes[model], speed_of(model)
        print
        return True

    CMD = "/opt/MegaRAID/MegaCli/MegaCli64"
    if not os.path.exists(CMD):
        # Why is it installed in two places??
        CMD = "/usr/sbin/MegaCli64"
        if not os.path.exists(CMD):
            return False

    # First parse out adapters
    proc = sudo([CMD, "-AdpAllInfo", "-aAll", "-NoLog"])
    adapters = dict()
    adapter = ""
    for line in proc.stdout:
        words = line.split()
        if len(words) < 2:
            continue
        if words[0] == "Adapter":
            adapter = words[1]
            adapters[adapter] = ""
        elif words[0:3] == ["Product", "Name", ":"]:
            adapters[adapter] += ' '.join(words[2:])
        elif words[0:3] == ["Memory", "Size", ":"]:
            adapters[adapter] += ' '.join(words[2:])

    proc.stdout.close()
    proc.wait()
    if len(adapters) < 1:
        # if package installed but not LSI hardware
        return False

    # now parse out the drives
    proc = sudo([CMD, "-LdPdInfo", "-aAll", "-NoLog"])
    print "Logical drives on LSI controllers:"
    if not parse_proc(proc, adapters):
        proc = sudo([CMD, "-PdList", "-aAll", "-NoLog"])
        parse_proc(proc, adapters, physical=True)
    return True

def do_hp():
    """
    Do HP platform specific reporting
    """

    CMD = "/usr/sbin/hpacucli"
    if not os.path.exists(CMD):
        return False
    proc = sudo([CMD,
                "controller", "all", "show", "config", "detail"])
    # state of the hpacucli parser, logical or physical
    mode = None

    # map of "logical drives"
    logicals = dict()
    logical = 1
    chunk = 1
    raid = "0"
    print "Logical drives on HP controllers:"

    # maps of physical drive properties
    counts = dict()
    sizes = dict()
    speeds = dict()
    size = ""
    speed = ""
    for line in proc.stdout:
        words = line.split()
        if len(words) < 1:
            mode = None
            continue
        if words[0:2] == ["Smart", "Array"]:
            if logicals:
                print_drives(logicals)
                logicals = dict()
            print ' '.join(words[2:])
        elif words[0:2] == ["Logical", "Drive:"]:
            mode = "logical"
            logical = int(words[2])
            logicals[logical] = ""
            continue
        elif words[0] == "physicaldrive":
            mode = "physical"

        if mode == "logical":
            if words[0:2] == ["Fault", "Tolerance:"]:
                if words[2] == "RAID" and len(words) > 2:
                    raid = words[3]
                else:
                    raid = words[2]
            elif words[0] == "Size:":
                logicals[logical] += ' '.join(words[1:]) + " "
            elif words[0:2] == ["Strip", "Size:"]:
                chunk = int(words[2])
            elif words[0:3] == ["Full", "Stripe", "Size:"]:
                width = int(words[3])/chunk
                if width > 1:
                    logicals[logical] += "%d KB X %d " % (chunk, width)
                if raid != "0":
                    logicals[logical] += "RAID " + raid + " "
            elif words[0:2] == ["Disk", "Name:"]:
                logicals[logical] += words[2] + " "
            elif words[0] == "Status:":
                logicals[logical] += words[1] + " "

        if mode == "physical":
            if words[0] == "Size:":
                size = ' '.join(words[1:])
            elif words[0:4] == ["Interface", "Type:",
                                "Solid", "State"]:
                speed = "SSD"
            elif words[0:2] == ["Rotational", "Speed:"]:
                speed = ' '.join(words[2:])
                if speed == "10000":
                    speed = "10K RPM"
                elif speed == "15000":
                    speed = "15K RPM"
            elif words[0] == "Model:":
                model =' '.join(words[1:])
                if model in counts:
                    counts[model] += 1
                else:
                    counts[model] = 1
                sizes[model] = size
                speeds[model] = speed

    proc.stdout.close()
    proc.wait()
    if logicals:
        print_drives(logicals)
    print "Physical drives:"
    for model in counts:
        print " ", counts[model], "x", model, sizes[model], speeds[model]
    print
    return True

def do_net():
    """
    For clusters (and perhaps remote loading, etc.)
    the network configuration might also be useful.
    Also find the PCIe flash devices in OnMetal.
    """

    proc = sudo(["lspci"])
    flashes = dict()
    nets = dict()
    for line in proc.stdout:
        words = line.split()
        if len(words) < 2:
            continue

        # Do something with this some day
        address = words.pop(0)

        if "Flash" in words:
            if words[0:3] == ["Serial", "Attached", "SCSI"]:
                del words[0:4]
                adapter = ' '.join(words)
                if adapter in flashes:
                    flashes[adapter] += 1
                else:
                    flashes[adapter] = 1
                continue
        if words[0] not in ["Ethernet", "Network"]:
                 continue
        del words[0:2]
        for noisy in ["Corporation", "Technologies"]:
            if noisy in words:
                words.remove(noisy)

        adapter = ' '.join(words)
        if adapter in nets:
            nets[adapter] += 1
        else:
            nets[adapter] = 1

    if len(flashes):
        print
        print "Storage:"
        for adapter in flashes:
            print " %d x %s" % (flashes[adapter], adapter)

    if len(nets) < 1:
        return
    print "Network interface controllers:"
    for adapter in nets:
        print " %d x %s" % (nets[adapter], adapter)

def do_hadoop():
    " record some Hadoop parameters that might be relevant to performance "

    proc = subprocess.Popen(["which", "hdfs"],
                             stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
    words = proc.stdout.read().split()
    proc.wait()
    if len(words) > 2:
        return
    print
    cmd = words[0].rstrip()
    proc = subprocess.Popen([cmd, "getconf", "-confKey", "dfs.blocksize"],
                             stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
    try:
        blk = int(proc.stdout.read())
    except ValueError:
        blk = None
    proc.wait()
    if blk:
        print "HDFS block size", blk/(1024*1024), "MB",
    else:
        print "HDFS block size unknown?",
    proc = subprocess.Popen([cmd, "getconf", "-confKey", "dfs.datanode.max.transfer.threads"],
                             stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT)
    threads = proc.stdout.read()
    proc.wait()
    print "data threads", threads

def main():
    """
    Invoke the discovery modules desired
    Some day, parse command line to subset them?
    """
    do_mem()
    cores = do_cpu()
    do_os()
    foundhp = do_hp()
    foundlsi = do_lsi()
    if not foundhp and not foundlsi:
        print "Did not find HP nor LSI disk controller software"
    do_net()
    do_hadoop()
    return cores

if __name__ == "__main__":
    main()
