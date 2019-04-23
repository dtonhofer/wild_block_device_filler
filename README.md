# wild_block_device_filler

## What is this

A simple Perl program to fill a partition or a disk with lots of 0x00, 0xFF or alphanumerics. Meant for Linux/Unix.

It calls the tool `lsblk(8)` to get information about available block devices, so you must have that on your system!

At 650+ lines, it looks complex, but the complexity resides in the handling of the input options mainly.

Good for:

   * Speed testing (how does throughput change when writing 100 physical blocks vs 1000 physical blocks?)
   * Erasing the disk, filling it with zeros.
   * Seeing what the SSD does, and whether TRIMs did anything etc.
   
## Status

Works perfectly well on Fedora 29.

## License

The UNLICENSE: https://unlicense.org/

> This is free and unencumbered software released into the public domain.

## How to deploy

   * Make sure the `lsblk(8)` tool exists on your machine.
   * Put the single Perl script wherever you prefer. Make it executable.
   * Make sure needed Perl modules have been installed. 
   
Non-core Perl modules that you need are:

   * `JSON::Parse`
   * `File::Sync`

On systems that use `dnf` as installer:

    dnf install perl-JSON-Parse perl-File-Sync

## Usage

To be able to write to the block device, this program must (most probably) be run as `root`!

The `--help` option says:

    Fill a partition or a disk with meaningless data.

    --dev=<DEV>       Device file, must be given. '/dev/sdbx', 'sdbx', '/dev/sdg', 'sdg'
                      are accepted here.

    --debug           Write debugging output to stderr.

    --sync            Call fdatasync(2) after each write operation, flushing data to disk. 
                      Recommended otherwise it looks as if the program is very fast, but
                      it just fills up the memory buffers.

    --fillpat=<PAT>   Fill pattern. Currently there is:
                      > 'zero','0' for 0x00
                      > 'one','1'  for 0xFF
                      > 'alpha'    for 'ABCD...'
                      > 'moon'     for the message from Iain M. Banks' 'The Algebraist'
                      Default is: alpha

    --chunksize=<SZ>  We write "chunks", not blocks. A chunk is an array of bytes sized 
                      at several KiB, MiB or multiples of the disk's PHYSICAL BLOCK SIZE
                      (amount of data that the disk prefers to read/write in one operation,
                      e.g. 4K) or multiples of the disk's LOGICAL BLOCK SIZE (smaller or equal
                      to the physical block size, for fine-grained, but slow addressing).
                      This sets the chunk size. Format is <num><unit>, where <unit> is one of:
                      > Nothing or 'B' for Byte
                      > 'K' for KiB
                      > 'M' for MiB
                      > 'P' for physical blocks
                      > 'L' for logical blocks
                      Default is: 1024L

When you start the program (on the command line, naturally) using for example:

    wildly_fill_block_device.pl --dev=sdb1 --fillpat 0 --chunksize=1024P --sync
   
It will pointedly ask you first:

    Going on will DESTROY device /dev/sdb1 -- are you sure to continue? Type YES!!

If you decide to proceed, you will get an information scroll:

    Wrote:   2658 chunks,   1329.00 MiB, 1.09% - Overall: 73.67 MiB/s - Recent: 73.87 MiB/s - time taken: 00:00:18 - ~time remaining: 00:27:14
    Wrote:   2953 chunks,   1476.50 MiB, 1.21% - Overall: 73.68 MiB/s - Recent: 74.29 MiB/s - time taken: 00:00:20 - ~time remaining: 00:27:03
    Wrote:   3244 chunks,   1622.00 MiB, 1.33% - Overall: 73.59 MiB/s - Recent: 73.51 MiB/s - time taken: 00:00:22 - ~time remaining: 00:27:18
    Wrote:   3537 chunks,   1768.50 MiB, 1.45% - Overall: 73.54 MiB/s - Recent: 72.05 MiB/s - time taken: 00:00:24 - ~time remaining: 00:27:49
    Wrote:   3832 chunks,   1916.00 MiB, 1.57% - Overall: 73.54 MiB/s - Recent: 73.27 MiB/s - time taken: 00:00:26 - ~time remaining: 00:27:19
    Wrote:   4122 chunks,   2061.00 MiB, 1.69% - Overall: 73.45 MiB/s - Recent: 72.31 MiB/s - time taken: 00:00:28 - ~time remaining: 00:27:39
    Wrote:   4414 chunks,   2207.00 MiB, 1.81% - Overall: 73.42 MiB/s - Recent: 73.98 MiB/s - time taken: 00:00:30 - ~time remaining: 00:27:00
    Wrote:   4704 chunks,   2352.00 MiB, 1.93% - Overall: 73.36 MiB/s - Recent: 72.81 MiB/s - time taken: 00:00:32 - ~time remaining: 00:27:24
    Wrote:   4998 chunks,   2499.00 MiB, 2.05% - Overall: 73.36 MiB/s - Recent: 73.94 MiB/s - time taken: 00:00:34 - ~time remaining: 00:26:57

At the end of filling an SSD, you will see a major slowdown as reallocation stalls:

    Wrote: 244049 chunks, 122024.50 MiB, 99.96% - Overall: 65.59 MiB/s - Recent: 5.81 MiB/s - time taken: 00:31:00 - ~time remaining: 00:00:08
    Wrote: 244071 chunks, 122035.50 MiB, 99.97% - Overall: 65.52 MiB/s - Recent: 5.80 MiB/s - time taken: 00:31:02 - ~time remaining: 00:00:06
    Wrote: 244093 chunks, 122046.50 MiB, 99.98% - Overall: 65.46 MiB/s - Recent: 5.39 MiB/s - time taken: 00:31:04 - ~time remaining: 00:00:04
    Wrote: 244122 chunks, 122061.00 MiB, 99.99% - Overall: 65.39 MiB/s - Recent: 5.81 MiB/s - time taken: 00:31:06 - ~time remaining: 00:00:01
    Wrote: 244144 chunks, 122072.00 MiB, 100.00% - Overall: 65.33 MiB/s - Recent: 5.83 MiB/s - time taken: 00:31:08 - ~time remaining: 00:00:00
    Wrote: 244145 chunks, 122072.34 MiB, 100.00% - Overall: 65.33 MiB/s - Recent: 5.84 MiB/s - time taken: 00:31:08 - ~time remaining: 00:00:00
