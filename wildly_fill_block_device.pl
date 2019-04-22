#!/usr/bin/perl

# 23456789012345678901234567890123456789012345678901234567890123456789012345678901234567
# ======================================================================================
# This program writes a disk or partition full of ones, zeros or alphanumerics.
# Good for speed testing, erasing, or evaluating what the SSD does.
#
# ===
# Authors: David Tonhofer (2019-04)
# License: "The Unlicense" (https://unlicense.org/)
#          This is free and unencumbered software released into the public domain.
# ===
#
# The program calls "lsblk" to get information about the system. So you need to have
# that utility.
#
# Additionally, you may have to install the following perl modules:
#
# JSON::Parse - install with:  dnf install perl-JSON-Parse
# File::Sync  - install with:  dnf install perl-File-Sync
#
# The "--help" option says:
#
# Fill a partition or a disk with meaningless data.
#
# --dev=<DEV>       Device file, must be given. '/dev/sdbx', 'sdbx', '/dev/sdg', 'sdg'
#                   are accepted here.
#
# --debug           Write debugging output to stderr.
#
# --sync            Call fdatasync(2) after each write operation, flushing data to disk. 
#                   Recommended otherwise it looks as if the program is very fast, but
#                   it just fills up the memory buffers.
#
# --fillpat=<PAT>   Fill pattern currently provided:: 
#                   'zero','0' for 0x00
#                   'one','1'  for 0xFF
#                   'alpha'    for 'ABCD...' (the default)
#
# --chunksize=<SZ>  We write "chunks", not blocks. A chunk is an array of bytes sized 
#                   at several KiB, MiB or multiples of the disk's PHYSICAL BLOCK SIZE
#                   (amount of data that the disk prefers to read/write in one operation,
#                   e.g. 4K) or multiples of the disk's LOGICAL BLOCK SIZE (smaller or equal
#                   to the physical block size, for fine-grained, but slow addressing).
#                   This sets the chunk size. Format is <num><unit>, where <unit> is one of:
#                   > Nothing or 'B' for Byte
#                   > 'K' for KiB
#                   > 'M' for MiB
#                   > 'P' for physical blocks
#                   > 'L' for logical blocks
#                   Default is: 1024L.
#

use JSON::Parse qw(parse_json);     # dnf install perl-JSON-Parse
use Data::Dumper;                   # Perl core module (to dump data structures)
use Fcntl qw(SEEK_SET);             # Perl core module
use File::Sync qw(fsync fdatasync); # dnf install perl-File-Sync
use Getopt::Long;                   # Perl core module (to process long options)
use File::Basename;                 # Perl core module (to obtain file basename & dirname)
use File::Spec;                     # Perl core module (https://perldoc.perl.org/File/Spec.html)
use Time::HiRes;                    # Perl core module;

use warnings;
use strict;
use utf8;  # Meaning "This lexical scope (i.e. file) contains utf8"

my $lsblk = "/usr/bin/lsblk";

main();

# ===
# This is the main function
# ===

sub main {

   # Process command line, which returns a hash of values found.
   #
   #      'cs_unit' => 'L',
   #      'cs_val'  => 1024,
   #      'debug'   => 1,
   #      'dev'     => '/dev/sdb1',
   #      'fillpat' => 'alpha',
   #      'sync'    => 0

   my $params = handleCmdlineArgs();

   if ($$params{debug}) {
      print STDERR Data::Dumper->new([$params])->Sortkeys(1)->Dump;
   }

   # Using the "device name" found on the command line, use lsblk to get info

   my $myBlockDev;

   {
      my $json = getDeviceInfoAsJson($params);
      if ($$params{debug}) {
         print STDERR @$json
      }
      $myBlockDev = extractDeviceInfoFromJson($json,$params);
   }

   # Safety first!

   {
      print STDERR "Going on will DESTROY device " . $$params{dev} . " -- are you sure to continue? Type YES!!\n";
      chomp(my $input = <> );
      if (lc($input) eq 'yes') {
         print STDERR "Continuing\n";
      }
      else {
         print STDERR "Stopping!\n";
         exit 1
      }
   }

   # Get more information about the device! 
   # (We don't know about "alignment", for this we would have to examine the partition table)

   my $phyBlockSize = $$myBlockDev{'phy-sec'};  # bytes; physical block size -> what is best read/written in one operation
   my $logBlockSize = $$myBlockDev{'log-sec'};  # bytes; logical block size  -> a part of the physical block if you want sub-physical but slow addressing
   my $devSize      = $$myBlockDev{size};       # bytes; total device size

   if (! defined $logBlockSize || $logBlockSize <= 0) {
      die "Logical block size is bad: $logBlockSize\n"
   }

   if (! defined $phyBlockSize || $phyBlockSize <= 0) {
      die "Physical block size is bad: $phyBlockSize\n"
   }

   if (! defined $devSize || $devSize <= 0) {
      die "Device size is bad: $devSize\n"
   }

   if ($logBlockSize > $phyBlockSize) {
      die "Physical block size is less than logical block size\n"
   }

   if ($devSize % $phyBlockSize != 0) {
      die "Device size $devSize is not an integer multiple of physical block size $phyBlockSize\n"
   }

   # We write in "chunks", multiple Kib, Mib; logical or physical blocks
 
   my $chunkSize = computeChunkSizeInByte($$params{cs_val},$$params{cs_unit},$phyBlockSize,$logBlockSize);

   if ($chunkSize % $logBlockSize != 0) {
      die "Chunk size $chunkSize is not an integer multiple of logical block size $logBlockSize\n"
   }

   if ($chunkSize > 128 * 1024 * 1024) {
      die "Chunk size $chunkSize is above 128 MiB (kinda large)\n"
   }

   print STDERR "Will write chunks of $chunkSize bytes ($$params{cs_val} $$params{cs_unit})\n";

   my $chunk = prepareChunk($$params{fillpat},$chunkSize);

   # Now write the chunk to disk multiple times
   # There may be a rest at the end of less than "packed" array size bytes (a multiple of logical blocks)
   # which is handled separately.

   open (my $devfh, ">", $$params{dev}) or die "Could not open device " . $$params{dev} . " for writing: $!";

   my $bytesToWrite  = $devSize; # this value counts down to 0
   my $chunksWritten = 0;        # this value counts up from 0; at the very end, writing may involve a partial chunk

   my $whenStarted    = Time::HiRes::time();   # floating point time; to compute overall throughput
   my $timings        = [ [$whenStarted,0] ];  # array of "time of writing done, bytes written" to compute recent throughput
   my $timingsDepth   = 100;                   # keep 100 entries to compute recent throughput
   my $nextInform     = $whenStarted;          # when to call informUser()
   my $informInterval = 2;                     # seconds

   # The loop:
   #   1) seek to writing position
   #   2) write a chunk or less than a chunk at the end of the device
   #   3) sync if so demanded
   #   4) inform user about how much has been written so far

   while ($bytesToWrite > 0) {

      my $writePos = $chunkSize * $chunksWritten;
      my $canWrite = min($bytesToWrite,$chunkSize);

      seek($devfh, $writePos, SEEK_SET) or die "Could not seek to position $writePos: $!\n";

      my $actuallyWritten = syswrite($devfh,$chunk,$canWrite); # write whole or part of chunk at the end

      if (!defined $actuallyWritten) {
         die "Could not write $canWrite bytes at position $writePos: $!\n"
      }
      if ($actuallyWritten != $canWrite) {
         die "Could only write $actuallyWritten bytes instead of $canWrite bytes at position $writePos: $!\n"
      }
 
      if ($$params{sync}) {
         fdatasync($devfh) or die "fdatasync failed: $!\n"
      }

      $chunksWritten++; 
      $bytesToWrite -= $actuallyWritten;
      my $now = Time::HiRes::time();
      push @$timings, [ $now, $actuallyWritten ];         # add timing at end
      if (@$timings > $timingsDepth) { shift @$timings }  # keep limited number of timings

      if ($now >= $nextInform || $bytesToWrite == 0) {
         informUser($devSize,$bytesToWrite,$whenStarted,$chunksWritten,$timings);
         $nextInform = $now + $informInterval
      }
   }

   close($devfh) or die "Could not close device " . $$params{dev} . ": $!\n";

   die "bytesToWrite should be 0 at end of loop but is $bytesToWrite" if $bytesToWrite != 0;

}

# ===
# Get information about the device using "lsblk" tool. As a string in JSON format.
# ===

sub getDeviceInfoAsJson {
   my($params) = @_;
   my $deviceFile = $$params{dev};
   my @json;
   
   # Execute "lsblk", generating JSON output.
   # Not sure what the encoding of the output of "lsblk" is. Depends on some
   # system setting, but it's probably UTF-8, with anything non-ASCII
   # encoded in the Json. Hairy. Let's not go deeper into this.
   
   # https://perldoc.perl.org/functions/open.html
   
   my $res = open(my $fh, "-|", $lsblk, "--output-all", "--bytes", "--json", $deviceFile);

   # "If the open involved a pipe, the return value happens to be the pid of the subprocess."
   # ...so we can't directly check whether "lsblk" returned an error code.
   # However, on problem, open() will have written something to STDERR and "$res" will be undef.

   if ($res) {
      print STDERR "PID of execution of $lsblk: $res\n" if $$params{debug};
      @json = <$fh>;
      close($fh) or die "Could not close pipe: $!\n";
   }
   else {
      print STDERR "Something went wrong executing $lsblk -- exiting!\n";
      exit 1
   }

   return \@json
}

# ===
# Parse JSON and extract the information that interests us
# ===

sub extractDeviceInfoFromJson {
   my($json,$params) = @_;
   my $deviceFile = $$params{dev};

   # https://metacpan.org/pod/distribution/JSON-Parse/lib/JSON/Parse.pod
   # parse_json throws a fatal error ("dies") if the input is ungood!

   my $singleString = join("\n",@$json);
   my $perlyData    = parse_json($singleString);
   
   # $perlyData must be a hash reference

   {
      my $got = ref $perlyData;
      print STDERR "We have obtained a $got\n" if $$params{debug};
      if ($got ne "HASH") {
         die "Did not obtain a hash reference parsing JSON, but a $got -- exiting!\n"
      }
   }

   # $perlyData must contain a key "blockdevices" listing the block devices that lsblk could read.
   # And the value of that key must be an array with 1 entry corresponding to our device of interest.

   if (!exists $$perlyData{blockdevices}) {
      die "No key 'blockdevices' in JSON obtained from '$lsblk $deviceFile' -- exiting!\n"
   }

   my $blockdevs = $$perlyData{blockdevices};

   if (@$blockdevs == 0) {
      die "Nothing in array listing blockdevices as obtained from '$lsblk $deviceFile' -- exiting!\n"
   }
   if (@$blockdevs != 1) {
      die "There should be exactly 1 entry in array listing blockdevices but there are " . scalar(@$blockdevs) . " -- exiting!\n"
   }

   my $myblockdev = $$blockdevs[0];

   print STDERR Data::Dumper->new([$myblockdev])->Sortkeys(1)->Dump if $$params{debug};

   if (basename($deviceFile) ne $$myblockdev{name}) {
      die "Device name mismatch: expected " . basename($deviceFile) . " but got " . $$myblockdev{name} . " -- exiting!\n"
   }
 
   my $type = $$myblockdev{type};

   if ($type ne "part" && $type ne "disk") {
      die "Blockdevice is not a 'part' (partition) nor a 'disk' but a '$type' -- exiting!\n"
   }

   return $myblockdev
}

# ===
# How large is the "chunk" to write?
# ===

sub computeChunkSizeInByte {
   my($cs_val,$cs_unit,$phyBlockSize,$logBlockSize) = @_;   
   my $chunkSize,   
   die if $cs_val <= 0;
   if ($cs_unit eq 'B') {
      $chunkSize = $cs_val
   }
   elsif ($cs_unit eq 'K') {
      $chunkSize = $cs_val * 1024
   }
   elsif ($cs_unit eq 'M') {
      $chunkSize = $cs_val * (1024 * 1024)
   }
   elsif ($cs_unit eq 'P') {
      $chunkSize = $cs_val * $phyBlockSize
   }
   elsif ($cs_unit eq 'L') {
      $chunkSize = $cs_val * $logBlockSize
   }
   else {
      die "Unknown unit '$cs_unit'"
   }
   return $chunkSize;
}

# ===
# Prepare the "large byte array" of the chunk
# ===

sub prepareChunk {
   my($fillpat,$chunkSize) = @_;
   my $buffer = []; # a LARGE buffer; no need to preallocate, we will just "push" to it!
   my $packed;      # a LARGE string of bytes
   if ($fillpat eq "zero") {
      for (my $i=0; $i<$chunkSize; $i++) {
         push @$buffer, 0
      } 
      $packed = pack "C*",@$buffer; # pack unsigned char array
   }
   elsif ($fillpat eq "one") {
      for (my $i=0; $i<$chunkSize; $i++) {
         push @$buffer, 255
      }
      $packed = pack "C*",@$buffer; # pack unsigned char array
   }
   elsif ($fillpat eq 'alpha') {
      my @template = qw(A B C D E F G H I J K L M N O P Q R S T U V W X Y Z 
                        a b c d e f g h i j k l m n o p q r s t u v w x y z
                        0 1 2 3 4 5 6 7 8 9);
      my $tsize = scalar(@template);
      my $tidx  = 0;
      for (my $i=0; $i<$chunkSize; $i++) {
         push @$buffer, $template[$tidx];
         $tidx = ($tidx + 1) % $tsize
      }
      $packed = pack "A*",join("",@$buffer); # pack ASCII array
   }
   elsif ($fillpat eq 'moon') {
      # The final message from Ian M. Banks' "The Algebraist" (c) 2004 Iain M. Banks
      my $template =
      "I was born in a water moon. Some people, especially its inhabitants, called it a planet, "
      ."but as it was only a little over two hundred kilometres in diameter, 'moon' seems the more "
      ."accurate term. The moon was made entirely of water, by which I mean it was a globe that not "
      ."only had no land, but no rock either, a sphere with no solid core at all, just liquid water, "
      ."all the way down to the very centre of the globe.\n\nIf it had been much bigger the moon would "
      ."have had a core of ice, for water, though supposedly incompressible, is not entirely so, "
      ."and will change under extremes of pressure to become ice. (If you are used to living on a "
      ."planet where ice floats on the surface of water, this seems odd and even wrong, but "
      ."nevertheless it is the case.) The moon was not quite of a size for an ice core to form, "
      ."and therefore one could, if one was sufficiently hardy, and adequately proof against the "
      ."water pressure, make one's way down, through the increasing weight of water above, to the "
      ."very centre of the moon.\n\nWhere a strange thing happened.\n\nFor here, at the very centre "
      ."of this watery globe, there seemed to be no gravity. There was colossal pressure, certainly, "
      ."pressing in from every side, but one was in effect weightless (on the outside of a planet, "
      ."moon or other body, watery or not, one is always being pulled towards its centre; once at "
      ."its centre one is being pulled equally in all directions), and indeed the pressure around "
      ."one was, for the same reason, not quite as great as one might have expected it to be, given "
      ."the mass of water that the moon was made up from.\n\nThis was, of course,";
      my $repeatTemplate = ""; # Ok, so this won't repeat exactly at chunk boundaries. SAD!
      my $lentemp = length($template);
      my $bytesToWrite = $chunkSize;
      while ($bytesToWrite >= $lentemp) { $repeatTemplate .= $template; $bytesToWrite -= $lentemp }
      $repeatTemplate .= substr($template,0,$bytesToWrite);
      $packed = pack "A*",$repeatTemplate
   }
   else {
      die "Unknown file pattern '$fillpat'\n"
   }
   die "Packed array has not the correct length; should be $chunkSize but is " . (length $packed) unless (length $packed) == $chunkSize;
   return $packed # TODO should one pass a reference here? Is copying optimized? I think so.
}

# ===
# Printing out while the write loop runs
# ===


sub informUser {
   my($devSize,$bytesToWrite,$whenStarted,$chunksWritten,$timings) = @_;

   my $mibFactor = 1048576.0;

   my $bytesWritten = ($devSize - $bytesToWrite);
   my $mibWritten   = $bytesWritten / $mibFactor;
   my $deltaOverall = Time::HiRes::time() - $whenStarted;

   my $baseMsg              = "Wrote: " . sprintf("%6d",$chunksWritten) . " chunks";
   my $doneSoFarMsg         = "";
   my $overallThroughputMsg = "";
   my $recentThroughputMsg  = "";
   my $timeRemainingMsg     = "";
   my $timeTakenMsg         = " - time taken: " . timeToHMS($deltaOverall);

   {
      my $percentDone  = ($bytesWritten * 100.0) / $devSize;
      my $percentDone2 = sprintf("%.2f",$percentDone);
      my $mibWritten2  = sprintf("%9.2f",$mibWritten);
      $doneSoFarMsg = ", $mibWritten2 MiB, $percentDone2%"
   }

   if ($deltaOverall >= 1) { # only after 1s
      my $mibPerSecond  = $mibWritten / $deltaOverall;
      my $mibPerSecond2 = sprintf("%.2f",$mibPerSecond); 
      $overallThroughputMsg = " - Overall: $mibPerSecond2 MiB/s";
   }

   if ($deltaOverall >= 1) { # only after 1s to get good numbers/not divide by 0
      # add the bytes written registered in "timings" so far, 
      # except the bytes of the oldest chunk (which is not considered in the total bytes)
      my $bytesWrittenRecently = 0;
      for (my $i = 1; $i < @$timings; $i++) {
         my $subArray          =  $$timings[$i];
         $bytesWrittenRecently += $$subArray[1];
      }
      if ($bytesWrittenRecently > 0) {
         # the "time taken" is the difference between the last timing 
         # (after most recent chunk written) and the first timing (after most ancient chunk written)
         my $subArrayFirst = $$timings[0];
         my $subArrayLast  = $$timings[-1];
         my $deltaRecently = $$subArrayLast[0] - $$subArrayFirst[0];
         my $mibWrittenRecently = $bytesWrittenRecently / $mibFactor;
         my $mibPerSecond       = $mibWrittenRecently / $deltaRecently;
         my $mibPerSecond2      = sprintf("%.2f",$mibPerSecond); 
         $recentThroughputMsg   = " - Recent: $mibPerSecond2 MiB/s";
         my $timeRemaining      = ( $bytesToWrite / $bytesWrittenRecently ) * $deltaRecently;
         $timeRemainingMsg      = " - ~time remaining: " . timeToHMS($timeRemaining)
      }
   }

   print STDERR $baseMsg, $doneSoFarMsg, $overallThroughputMsg, $recentThroughputMsg, $timeTakenMsg, $timeRemainingMsg, "\n";
}

# ===
# Helper from the PerlMonks
# ===

sub timeToHMS {
  my $seconds = int(shift);
  my $hours = int( $seconds / (60*60) );
  my $mins = ( $seconds / 60 ) % 60;
  my $secs = $seconds % 60;
  return sprintf("%02d:%02d:%02d", $hours,$mins,$secs);
}

# ===
# Deal with command line arguments
# ===

sub handleCmdlineArgs {

   my $deffip    = 'alpha';
   my $defckz    = '1024L';

   my $help      = 0;        # print help
   my $error     = 0;        # an error occurred, so exit 
   my $dev;                  # device file, must be given
   my $debug     = 0;        # write debugging output to stderr
   my $sync      = 0;        # call fdatasync(2) after write of chunk
   my $fillpat   = $deffip;  # fill pattern: '0' for 0x00, '1' for 0xFF, 'alpha' for "ABCD..."
   my $chunksize = $defckz;  # we write whole chunks of this size; encoded as <value><unit>, e.g. 1024L is 1024 logical blocks
   my $cs_val;               # chunksize value, parsed
   my $cs_unit;              # chunksize unit, parsed (one of B K M P L)

   my @options = (  "dev=s"             => \$dev
                   ,"debug"             => \$debug
                   ,"sync"              => \$sync
                   ,"fillpat=s"         => \$fillpat
                   ,"chunksize=s"       => \$chunksize
                   ,"help"              => \$help);

   if (!GetOptions(@options)) {
      $error = 1;
      $help = 1;
   }
   
   if (!$error && !$help) {
      if (trim($dev) eq '') {
         print STDERR "Device file must be given using 'dev' option!!\n";
         $error = 1
      }
   }

   if (!$error && !$help) {
      if (! -e $dev) {
         my $dev2 = File::Spec->catfile(File::Spec->rootdir(), "dev", $dev);
         if (! -e $dev2) {
            print STDERR "Neither device file '$dev' nor '$dev2' exist!\n";
            $error = 1;
         }
         else {
            $dev = $dev2
         }
      }
      # $dev is the name of a file that exists (maybe not a device or not a block device)
   }

   if (!$error && !$help) {
      if (trim($fillpat) ne '') {
         # if fillpat was not given on the command line, it has the default value
         $fillpat = lc(trim($fillpat))
      }
      else {
         print STDERR "The value of 'fillpat' has been set to empty!\n";
         $error = 1
      }
   }

   if (!$error && !$help) {
      if ($fillpat =~ /^1$|^one/) {
         $fillpat = 'one'
      }
      elsif ($fillpat =~ /^0$|^zero/) {
         $fillpat = 'zero'
      }
      elsif ($fillpat =~ /^alpha/) {
         $fillpat = 'alpha'
      }
      elsif ($fillpat =~ /^moon/) {
         $fillpat = 'moon'
      }
      else {
         print STDERR "Unknown fill pattern '$fillpat' - select one of 0,1,zero,one,alpha!\n";
         $error = 1
      }
   }

   if (!$error && !$help) {
      if (trim($chunksize) ne '') {
         # if chunksize was not given on the command line, it has the default value and we can parse it normally
         my $cs = uc(trim($chunksize));
         if ($cs =~ /^(\d+)(B|K|M|L|P)?$/) {
            $cs_val  = $1 * 1;
            $cs_unit = $2; $cs_unit = 'B' if (!$cs_unit);
            if ($cs_val == 0) {
               print STDERR "Chunksize must be > 0!\n";
               $error = 1;
            }
            elsif ($cs_unit eq 'B' && ($cs_val % 512 != 0 || $cs_val < 512)) {
               print STDERR "A chunksize in byte must be given as a multiple of 512!\n";
               $error = 1;
            }
            else {
               # Should we do further tests? That the value is a power of 2, not too large etc? 
               # Not for now, accept anything!
            }
         }
         else {
            print STDERR "The chunksize must be one of <num>, <num>B, <num>K, <num>M, <num>L, <num>P (default is $defckz)!\n";
            $error = 1
         }  
      }
      else {
         print STDERR "The value of 'chunksize' has been set to empty!\n";
         $error = 1
      }
   }

   if ($help) {
      print "\n\n" if ($error);
      {
         my $exe = basename($0);
         print STDERR "$exe\n";
         print STDERR "-" x length($exe), "\n";
      }
      print STDERR <<MSG
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
                  Default is: $deffip

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
                  Default is: $defckz
MSG
   }

   die  if $error;
   exit if $help;

   return {
      dev     => $dev 
      ,debug   => $debug
      ,sync    => $sync
      ,fillpat => $fillpat
      ,cs_val  => $cs_val
      ,cs_unit => $cs_unit
   }
}

# ===
# Min of two numbers
# ===

sub min {
   my($a,$b) = @_;
   if ($a < $b) { return $a } else { return $b }
}

# ===
# Trim a string. Does not return "undef" but may return the empty string.
# ===

sub trim {
   my ($in) = @_;
   my $res;
   if (! defined $in) {
      $res = ''
   }
   else {
      if ($in =~ /^\s*(.*?)\s*$/) {
         $res = $1
      }
      else {
         die "Could not match string '$in'"
      }
   }
   return $res
}


