#!/usr/bin/env perl
# Read-only on-device regression check; no API key or chat content is printed.
use strict;
use warnings;
use IO::Socket::UNIX;
use Socket qw(SOCK_STREAM);
use JSON::PP;
sub rpc {
    my ($method,$params)=@_;
    my $socket=IO::Socket::UNIX->new(Type=>SOCK_STREAM,Peer=>'/var/mobile/Library/AgentHome/agent.sock') or die "Connect: $!\n";
    $socket->autoflush(1); alarm 10;
    print $socket encode_json({id=>'regression',method=>$method,params=>$params})."\n";
    my $line=<$socket>; close $socket; alarm 0;
    die "Incomplete response\n" unless defined $line;
    my $reply=decode_json($line); die "$method: $reply->{error}\n" if $reply->{error}; return $reply->{result};
}
my $info=rpc('system.info',{}); die "Invalid storage\n" unless $info->{free_bytes}>=0;
my $conversations=rpc('chat.conversations',{})->{conversations};
for my $conversation (@$conversations) {
    my $context=rpc('context.status',{conversation_id=>$conversation->{id}});
    die "Invalid context counts\n" unless defined($context->{omitted_recent}) && $context->{omitted_recent}>=0 && $context->{characters}>=0 && $context->{characters}<=$context->{budget};
}
print 'PASS: daemon IPC, conversations, Context status on '.scalar(@$conversations)." conversations\n";
