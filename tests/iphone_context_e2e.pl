#!/usr/bin/env perl
# Run on iPhone. Metadata profile JSON only; daemon reads the API key in Keychain.
# perl iphone_context_e2e.pl PHASE PROFILE_JSON STATE_JSON [ARG]
# PHASE: begin seed compact poll activate recall search switch auto restore cancel long-answer probe cleanup
use strict;
use warnings;
use IO::Socket::UNIX;
use Socket qw(SOCK_STREAM);
use JSON::PP;
umask 0077;
my ($phase,$profile_path,$state_path,$argument)=@ARGV;
die "Usage: PHASE PROFILE_JSON /var/mobile/Library/AgentHome/eval-NAME.json [ARG]\n" unless $phase && $profile_path && $state_path && $state_path =~ m{^/var/mobile/Library/AgentHome/eval-[A-Za-z0-9_-]+\.json$};
sub read_json { my($path)=@_; open my $in,'<',$path or die "$path: $!\n"; local $/; return decode_json(<$in>); }
sub rpc {
    my ($method,$params)=@_;
    my $socket=IO::Socket::UNIX->new(Type=>SOCK_STREAM,Peer=>'/var/mobile/Library/AgentHome/agent.sock') or die "Connect: $!\n";
    $socket->autoflush(1); alarm 20; print $socket encode_json({id=>'context-eval',method=>$method,params=>$params})."\n";
    my $line=<$socket>; close $socket; alarm 0; die "Incomplete response\n" unless defined $line;
    my $reply=decode_json($line); die "$method: $reply->{error}\n" if $reply->{error}; return $reply->{result};
}
sub profile {
    my $input=read_json($_[0]); my %allowed=map {$_=>1} qw(id endpoint model disableStreaming context_window_tokens max_output_tokens);
    die "Profile must contain metadata only, no API key\n" if grep {!$allowed{$_}} keys %$input;
    die "Invalid metadata profile\n" unless $input->{id} && $input->{endpoint} && $input->{model};
    return $input;
}
my $state;
if($phase eq 'begin') {
    die "State file already exists; cleanup first\n" if -e $state_path;
    my $config=profile($profile_path); $config->{context_window_tokens}=200000 unless $config->{context_window_tokens};
    my $created=rpc('chat.create',{});
    $state={kind=>'agenthome-context-eval-v1',conversation=>$created->{id},conversations=>[$created->{id}],profile=>$config,cycle=>0,snapshots=>[]};
} else { $state=read_json($state_path); die "Not an eval state file\n" unless $state->{kind} eq 'agenthome-context-eval-v1'; }
my $conversation=$state->{conversation}; my $result={phase=>$phase,conversation=>$conversation};
if($phase eq 'seed') {
    my $cycle=++$state->{cycle}; my $font=13+$cycle;
    for my $i (0..243) {
        my $content="Synthetic cycle $cycle log $i. ".('Read-only diagnostic; preserve all data. ' x 10);
        $content="Project LOTUS-482; report file /tmp/agenthome-eval/report.txt. ".$content if $i==0;
        $content="Final font is $font. Ticket T-42 HTTP 404 at /v1/chat/completions. Build and iPhone verification are NOT done. Only device info read is authorized; shell and deploy are NOT authorized. Next step: inspect endpoint. ".$content if $i==230;
        rpc('chat.append',{conversation_id=>$conversation,role=>($i%2?'assistant':'user'),content=>$content});
    }
    $result->{cycle}=$cycle; $result->{expected_font}=$font;
} elsif($phase eq 'compact') {
    $result->{job}=rpc('context.compact',{conversation_id=>$conversation,profile=>$state->{profile}});
} elsif($phase eq 'poll') {
    my $context=rpc('context.status',{conversation_id=>$conversation,profile=>$state->{profile}});
    $result->{context}=$context; $result->{ai}=rpc('ai.snapshot',{conversation_id=>$conversation});
    $result->{total_messages}=rpc('chat.list',{conversation_id=>$conversation})->{total_messages};
} elsif($phase eq 'activate') {
    my $latest=rpc('context.status',{conversation_id=>$conversation,profile=>$state->{profile}})->{latest};
    die "No ready candidate\n" unless $latest->{state} eq 'ready';
    $result->{activation}=rpc('context.activate',{conversation_id=>$conversation,id=>$latest->{id}}); push @{$state->{snapshots}},$latest->{id};
} elsif($phase eq 'recall' || $phase eq 'long-answer') {
    my $task='eval-'.$phase.'-'.time;
    my $text=$phase eq 'recall'?'Return JSON only: project_id, report_path, final_font, ticket, http_error, endpoint, build_verified, shell_allowed, deploy_allowed. Search memory before returning unknown facts. No invented values.':'Write a detailed 1500-word explanation of how to organize a fictional garden. This is a background/lock test; do not use tools.';
    $result->{task}=rpc('ai.submit',{id=>$task,conversation_id=>$conversation,profile=>$state->{profile},text=>$text}); $state->{task}=$task;
} elsif($phase eq 'search') {
    $result->{search}=rpc('memory.search',{conversation_id=>$conversation,arguments=>{query=>$argument || 'project LOTUS-482',limit=>4}});
} elsif($phase eq 'switch') {
    my $next=profile($profile_path); die "Specify a genuinely different provider/model metadata profile\n" if $next->{id} eq $state->{profile}{id} && $next->{endpoint} eq $state->{profile}{endpoint} && $next->{model} eq $state->{profile}{model};
    $next->{context_window_tokens}=200000 unless $next->{context_window_tokens}; $state->{profile}=$next; $result->{model}=$next->{model};
} elsif($phase eq 'auto') {
    $result->{settings}=rpc('context.configure',{conversation_id=>$conversation,enabled=>JSON::PP::true,auto_activate=>JSON::PP::true,threshold=>50});
} elsif($phase eq 'restore') {
    my $checkpoints=rpc('context.checkpoints',{conversation_id=>$conversation})->{checkpoints};
    my ($previous)=grep {$_->{state} eq 'superseded'} @$checkpoints; die "No previous checkpoint\n" unless $previous;
    my $before=rpc('chat.list',{conversation_id=>$conversation})->{total_messages};
    $result->{restored}=rpc('context.restore',{conversation_id=>$conversation,id=>$previous->{id}});
    die "Transcript changed during restore\n" unless $before==rpc('chat.list',{conversation_id=>$conversation})->{total_messages};
} elsif($phase eq 'cancel') {
    die "No eval task\n" unless $state->{task}; $result->{cancel}=rpc('ai.cancel',{id=>$state->{task}});
} elsif($phase eq 'probe') {
    my $bytes=$argument || 24000; die "Probe payload must be 1000..480000 bytes\n" unless $bytes =~ /^\d+$/ && $bytes>=1000 && $bytes<=480000;
    srand(482); my $payload=join('',map {sprintf('%x',int(rand(16)))} 1..$bytes);
    for(my $offset=0;$offset<length($payload);$offset+=12000) {
        rpc('chat.append',{conversation_id=>$conversation,role=>'user',content=>substr($payload,$offset,12000)});
        rpc('chat.append',{conversation_id=>$conversation,role=>'assistant',content=>'Synthetic capacity test data recorded.'});
    }
    my %probe_profile=%{$state->{profile}}; $probe_profile{max_output_tokens}=256; $probe_profile{disableStreaming}=JSON::PP::true;
    $state->{profile}=\%probe_profile; my $task='eval-probe-'.time;
    $result->{task}=rpc('ai.submit',{id=>$task,conversation_id=>$conversation,profile=>\%probe_profile,text=>'Synthetic capacity check. Ignore hexadecimal data. Reply only PROBE_OK. Do not use tools.'});
    $state->{task}=$task; $result->{payload_bytes}=$bytes;
} elsif($phase eq 'cleanup') {
    for my $id (@{$state->{conversations}}) {
        my $ai=rpc('ai.snapshot',{conversation_id=>$id}); die "Eval task active; cancel/poll before cleanup\n" if ($ai->{state} || '') =~ /^(queued|running)$/;
        rpc('chat.delete',{conversation_id=>$id});
    }
    unlink $state_path; print encode_json({phase=>'cleanup',deleted=>scalar @{$state->{conversations}}})."\n"; exit;
} elsif($phase ne 'begin') { die "Unknown phase\n"; }
open my $out,'>',$state_path or die "$state_path: $!\n"; print $out encode_json($state); close $out;
print encode_json($result)."\n";
