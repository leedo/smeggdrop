#!/usr/bin/perl 

use strict;
use warnings;
use Config::General;
use Carp::Always;
use Data::Dump  qw/ddx/;
use POE         qw/Component::IRC::State Component::IRC::Plugin::Connector/;

use lib 'lib';
use Shittybot::TCL;

sub parse_config {
  my $configfile  = $ENV{'SMEGGDROP_CONFIG'} && (-r $ENV{'SMEGGDROP_CONFIG'}) ? 
                      $ENV{'SMEGGDROP_CONFIG'} : 'bot.conf';
  die "Config file does not exist" unless (-r $configfile);
  my $config      = Config::General->new($configfile) or die "Failed to read config file";

  my %configuration = $config->getall or die "Failed to parse configuration file";
  return \%configuration;
}

my %states;
my $config  = parse_config;

for my $server (keys %{$config->{Server}}) {
  my $conf  = $config->{Server}->{$server};


  my $nick      = $conf->{nickname} || 'dickbot',
  my $username  = $conf->{username} || 'urmom',
  my $ircname   = $conf->{realname} || 'loves dis bot',
  
  my $server    = $conf->{address} || warn "Unable to parse address for network $server" && next;
  my $port      = $conf->{port} || 6667;
  my $ssl       = $conf->{ssl}  ? 1 : 0;

  my $irc = POE::Component::IRC::State->spawn(
    nick      => $nick,
    username  => $username,
    ircname   => $ircname,

    server    => $server,
    port      => $port,
    usessl    => $ssl,
  ) or warn "Failed to spawn IRC component" && next;

  print "Spawned IRC component to $server $port with nick $nick, user $username, name $ircname ssl $ssl\n";

  if (!$states{$conf->{state}}) {
    my $tcl = Shittybot::TCL->spawn($conf->{state},$irc);
    $states{$conf->{state}} = $tcl;
    print "Spawned TCL master for state $conf->{state}\n";
  }


  POE::Session->create(
    package_states  => [
      main  => [qw/_default _start irc_001 irc_public/],
    ],
    heap  => {
      irc   => $irc,
      conf  => $conf,
      tcl   => $states{$conf->{state}},
    },
  );
}

sub _start {
  my ($kernel, $heap) = @_[KERNEL,HEAP];

  $heap->{irc}->yield(register  => 'all');
  $heap->{irc}->yield('connect');
}

sub irc_001 {
  my ($kernel, $heap) = @_[KERNEL,HEAP];

  print "Connected to ", $heap->{irc}->server_name, "\n";

  if(ref($heap->{conf}->{Channels}->{default})) {
    $heap->{irc}->yield(join => "#$_") for (@{$heap->{conf}->{Channels}->{default}});
  } else {
    $heap->{irc}->yield(join  => "#" . $heap->{conf}->{Channels}->{default});
  }
}

sub irc_public {
  my ($kernel,$heap,$who,$channels,$message)  = @_[KERNEL,HEAP,ARG0 .. ARG2];

  my $trigger = $heap->{conf}->{trigger};

  print STDERR "got message: $message\n";
  if ($message  =~ qr/$trigger/) {
    print "Got trigger $message\n";
    my $code  = $message;
    $code     =~ s/$trigger//;

    my $nick  = ($who =~ /^([^!]+)/)[0];
    my $mask  = $who;
    $mask     =~ s/^[^!]+!//;

    my $out   = $heap->{tcl}->call($nick,$mask,'',${$channels}[0],$code);

    $heap->{irc}->yield(privmsg  => ${$channels}[0]  => $_) for (split (/\n/,$out));
  }
}

sub _default {
  my ($kernel,$heap,$event,@args) = @_[KERNEL,HEAP,ARG0,ARG1 .. $#_];

#  ddx($event);
}

POE::Kernel->run();
