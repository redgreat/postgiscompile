#!/usr/bin/env perl
use strict;
use warnings;
use JSON::PP qw(decode_json encode_json);
use LWP::UserAgent;
use DBI;

# 函数: 加载配置文件
sub load_config {
    my ($path) = @_;
    open my $fh, "<:encoding(UTF-8)", $path or die "无法读取配置: $path";
    local $/;
    my $txt = <$fh>;
    close $fh;
    my $cfg = decode_json($txt);
    return $cfg;
}

# 函数: 发送企业微信告警
sub send_wechat {
    my ($webhook, $content) = @_;
    my $ua = LWP::UserAgent->new(timeout => 10);
    my $res = $ua->post($webhook,
        'Content-Type' => 'application/json',
        Content => encode_json({ msgtype => "text", text => { content => $content } })
    );
    return $res->is_success;
}

# 函数: 采集连接统计
sub get_connections {
    my ($dbh) = @_;
    my $sql = q{
        SELECT
          COUNT(*) FILTER (WHERE pid != pg_backend_pid()) AS total,
          COUNT(*) FILTER (WHERE state = 'active') AS active,
          COUNT(*) FILTER (WHERE state = 'idle') AS idle
        FROM pg_stat_activity
    };
    my $row = $dbh->selectrow_hashref($sql);
    return $row || { total => 0, active => 0, idle => 0 };
}

# 函数: 主入口
sub main {
    my $config = $ENV{MONITOR_PG_CONFIG} || "monitor/config/config.json";
    my $cfg = load_config($config);
    my $dsn = sprintf("dbi:Pg:dbname=%s;host=%s;port=%d", $cfg->{db}->{dbname}, $cfg->{db}->{host}, $cfg->{db}->{port});
    my $dbh = DBI->connect($dsn, $cfg->{db}->{user}, $cfg->{db}->{password}, { RaiseError => 1, AutoCommit => 1 });
    my $c = get_connections($dbh);
    my $msg = sprintf("[INFO] PostgreSQL 连接统计 total=%d active=%d idle=%d", $c->{total}, $c->{active}, $c->{idle});
    send_wechat($cfg->{webhook}->{url}, $msg);
}

main();

