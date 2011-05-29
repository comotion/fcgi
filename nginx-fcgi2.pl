#!/usr/bin/perl
#
#	Based on a script by:
#	author		Daniel Dominik Rudnicki
#	email		daniel@sardzent.org
#	version		0.4.2
#	webpage		http://www.nginx.eu/
#
#	BASED @ http://wiki.codemongers.com/NginxSimpleCGI
#
#       futher work based needed workind stdin/stdout
#       Kacper Wysocki, 2008-08-23
#       TODO: proper PIDfile logic. cleanup. rc script. logfile rotation. use strict
#
# use strict;
use FCGI;
use Getopt::Long;
use IO::All;
use Socket;
use IPC::Open2;
use Fcntl;
use File::Basename;

use POSIX qw( :sys_wait_h :errno_h);
my $piddir = "/var/run/nginx/pid/";
my $logfile = "/var/log/nginx/fcgi.log";
my $unixsocket = "/var/run/nginx/fcgi.sock";
sub REAPER {
   my $child;
#If a second child dies while in the signal handler caused by the
# first death, we won't get another signal. So must loop here else
# we will leave the unreaped child as a zombie. And the next time
# two children die we get another zombie. And so on.
   while (($child = waitpid(-1,WNOHANG)) > 0) {
      $Kid_Status{$child} = $?;
   }
   $SIG{CHLD} = \&REAPER;  # still loathe sysV
}
$SIG{CHLD} = \&REAPER;

sub d {
   print  STDERR @_ if $verbose;
}

sub init {
   GetOptions(	"h"	=> \$help,
               "v"=>\$verbose,
               "pid=s"	=> \$filepid,
               "l=s" => \$logfile,
               "S:s"   => \$unixsocket,
               "d" => \$daemonize,
               "P:i"   => \$unixport) or usage();
   usage() if $help;

   print "	Starting Nginx-fcgi\n" if $verbose;
   print "	Running with $> UID" if $verbose;
   print "	Perl $]" if $verbose;

   if ( $> == "0" ) {
      print "\n\tERROR\tYou musn't be root to run me!\n";
      exit 1;
   }

   if ( ! $logfile ) {
      print "\n\tERROR\t log file must be declared\n"
         . "\tuse $0 -l filename to do so\n\n";
      exit 1;
   }
   print "	Using log file $logfile\n" if $verbose;
   "\n\n" >> io($logfile);
   addlog($logfile, "Starting Nginx-cfgi");
   addlog($logfile, "Running with $> UID");
   addlog($logfile, "Perl $]");
   addlog($logfile, "Testing socket options");

   if ( ($unixsocket && $unixport) || (!($unixsocket) && !($unixport)) ) {
      print "\n\tERROR\tPlease specify either -S socket or -P port.\n";
      exit 1;
   }

   if ($unixsocket) {
      print "	Daemon listening at UNIX socket $unixsocket\n" if $versbose;
      addlog($logfile, "Deamon listening at UNIX socket $unixsocket");
   } else {
      print "	Daemon listening at TCP/IP socket *:$unixport\n" if $verbose;

      addlog($logfile, "Daemon listening at TCP/IP socket *:$unixport");
   }
      if ( $unixsocket ) {
         print "	Creating UNIX socket\n" if $verbose;
         $socket = FCGI::OpenSocket( $unixsocket, 10 );
         if ( !$socket) {
            print "	Couldn't create socket\n";
            addlog($logfile, "Couldn't create socket");
            exit 1;
         }
         print "	Using UNIX socket $unixsocket\n" if $verbose;
      } else {
         print "	Creating TCP/IP socket\n" if $verbose;
         $portnumber = ":".$unixport;
         $socket = FCGI::OpenSocket( $unixport, 10 );
         if ( !$socket ) {
            print "	Couldn't create socket\n";
            addlog($logfile, "Couldn't create socket");
            exit 1;
         }
         print " Using port $unixport\n" if $verbose;
      }
   addlog($logfile, "Socket created");
   kill_env()
}
sub kill_env(){
  for (keys %ENV){
    delete $ENV{$_};
  }
}


sub do_pidfile()
{
   my $pid = $$;
   my $prog = basename $0;
   my $pf = $piddir.$prog.'.';

   open(my $pidfile, '>', $pf.$pid) or die "failed to open pidfile $pf$pid";
   opendir(PIDDIR,$piddir) or die "failed to open $piddir";
   d "$prog up on $pid. rummaging thru $piddir\n";
   for (readdir PIDDIR){
      if (/^\.\.?$/){
         next;
      }elsif(/$prog\.(\d+)/ and $1 ne $pid) {
         if(kill 0, $1){
            unlink $pf.$pid;
            close $pidfile;
            die "$prog already running at pid $1\n";
         }else{
            unlink $piddir.$_ or die "failed to unlink $piddir.$_";
            d "unlinked stale pidfile for pid $_\n";
         }
      }
   }
   #$SIG{'TERM'} = sub { unlink $piddir.$pid and die "$prog caught SIGTERM\n" };

   closedir PIDDIR;
   return $pid;
}

sub addzero {
   my ($date) = shift;
   if ($date < 10) {
      return "0$date";
   }
   return $date;
}

sub logformat {
   my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$iddst) = localtime(time);
   my $datestring;
   $year += 1900;
   $mon++;
   $mon  = addzero($mon);
   $mday = addzero($mday);
   $min  = addzero($min);
   $datestring = "$year-$mon-$mday $hour:$min";
   return($datestring);
}

sub addlog {
   my ($log_file, $log_message) = @_;
   my $curr_time = logformat();
   my $write_message = "[$curr_time]   $log_message";
   $write_message >> io($log_file);
   "\n" >> io($log_file);
}

sub printerror {
   my $message = @_;
   print "\n	Nginx FastCGI\tERROR\n"
      . "\t $message\n\n";
   exit 1;
}

sub usage {
   print "\n	Nginx FastCGI \n"
      . "\n\tusage: $0 [-h] -S string -P int\n"
      . "\n\t-h\t\t: this (help) message"
      . "\n\t-S path\t\t: path for UNIX socket"
      . "\n\t-P port\t\t: port number"
      . "\n\t-p file\t\t: path for pid file"
      . "\n\t-l file\t\t: path for logfile"
      . "\n\n\texample: $0 -S /var/run/nginx-perl_cgi.sock -l /var/log/nginx/nginx-cfgi.log -pid /var/run/nginx-fcgi.pid\n\n";
   exit 1;
}


init;
#
END() { } BEGIN() { }
*CORE::GLOBAL::exit = sub { die "fakeexit\nrc=".shift()."\n"; }; eval q{exit}; 
if ($@) { 
   exit unless $@ =~ /^fakeexit/; 
} ;

# fork part
my $pid = fork() if $daemonize;

if( $pid == 0 ) {
# this is the child
   do_pidfile();
      &main;
   exit 0;
}
# parent
if ( kill 0, $pid ){
   my $msg = "worker @ pid $pid, parent process $$ exiting";
   d($msg."\n");
   addlog($logfile, $msg);
   exit 0;
}else{
   my $msg = "worker @ pid $pid was stillborne. Parent will sulk and die.";
   addlog($logfile, $msg);
   die $msg;
}

sub main {
   $request = FCGI::Request( \*STDIN, \*STDOUT, \*STDERR, \%req_params, $socket );

   #my ($req_in, $req_out);
   #$request = FCGI::Request( $req_in, $req_out, \*STDERR, \%req_params, $socket );
   if ($request) { request_loop()};
   FCGI::CloseSocket( $socket );
}
sub errio {
   print("Content-type: text/plain\r\n\r\n");
   print "Error: CGI app returned no output - Executing $req_params{SCRIPT_FILENAME} failed !\n";
   addlog($logfile, "Error: CGI app returned no output - Executing $req_params{SCRIPT_FILENAME} failed !");
}


sub request_loop {
   while( $request->Accept() >= 0 ) {
      # processing any STDIN input from WebServer (for CGI-POST actions)
      addlog($logfile,"[$req_params{'SERVER_NAME'}/$req_params{'SERVER_ADDR'}:$req_params{'SERVER_PORT'}] $req_params{'REMOTE_ADDR'}:$req_params{'REMOTE_PORT'} | ID:$cnt |$req_params{'REQUEST_METHOD'}| len:$req_params{'CONTENT_LENGTH'}" | $req_params{'CONTENT_TYPE'});

      $req_len = 0 + $req_params{'CONTENT_LENGTH'};
      read(STDIN, $stdin_line, $req_params{'CONTENT_LENGTH'}); # not exactly streaming.. more like 'rammin'
      # running the cgi app
      kill_env();
      if ( (-x $req_params{SCRIPT_FILENAME}) && 
           (not -d $req_params{SCRIPT_FILENAME}) &&
           (-s $req_params{SCRIPT_FILENAME}) && 
           (-r $req_params{SCRIPT_FILENAME}))
      {

         foreach $key ( keys %req_params){
            $ENV{$key} = $req_params{$key};
         }
         if ( $verbose ) {
            addlog($logfile, "running $req_params{SCRIPT_FILENAME}");
         }
         # fuck that pipe open noize- we need bidirectional!!!
         #$pid = open2(\*STDOUT,\*STDIN, $req_params{SCRIPT_FILENAME})or errio;
         chdir dirname($req_params{SCRIPT_FILENAME});
         my ($req_in, $req_out, $req_err);
         $pid = open2($req_out, $req_in, $req_params{SCRIPT_FILENAME})or errio;

          # pass input to the program
         print $req_in $stdin_line;
         close $req_in; # EOF

=errorchecker disabled for fun times :-X
         # check for errors
         my $flags = '';
         fcntl($req_err, F_GETFL, $flags)
           or print STDERR "Couldn't get flags for HANDLE : $!\n";
         $flags |= O_NONBLOCK;
         fcntl($req_err, F_SETFL, $flags)
           or print STDERR "Couldn't set flags for HANDLE: $!\n";
         my ($buf, $sz) = ('', 1024);
         my $rv = sysread($req_err, $buf, $sz);
         if(!defined($rv) && $! == EAGAIN){
           addlog($logfile, "no stderr, no prob");
           print STDERR "no stderr, no prob";
         }else{
           addlog($logfile, "Problem: $buf");
           print STDERR "problem: $buf";
         }
         close $req_err;
=cut
         # wait for output (there gotta be some)
         while(<$req_out>){
            print;
         }
         #close $req_out;
         addlog($logfile, "spawned $req_params{SCRIPT_FILENAME} @ $pid");

      } else {
         print("Content-type: text/plain\r\n\r\n");
         print "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not exist or is not executable by this process.\n";
         addlog($logfile, "Error: No such CGI app - $req_params{SCRIPT_FILENAME} may not exist or is not executable by this process.");
      }
   }
}
