use List::Util qw(sum);

use Storable ();

my $SD_VERSION = 1;

my $ignore = qr/ ^(?:robots.txt$|\.) /x;

our %diridx;

if ($db_env) {
   tie %diridx, BerkeleyDB::Hash,
       -Env => $db_env,
       -Filename => "directory",
       -Flags => DB_CREATE,
          or die "unable to create database index";
}

sub conn::gen_statdata {
   my $self = shift;
   my $data;
   
   {
      my $path = "";
      my $prefix = "";

      for ("http://".$self->server_hostport, split /\//, substr $self->{name}, 1) {
         next if $_ eq ".";
         $path .= "<a href='".escape_uri("$prefix$_")."/'>$_</a> / ";
         $prefix .= "$_/";
      }
      $data->{path} = $path;
   }

   sub read_file {
      local ($/, *X);
      (open X, "<$_[0]\x00") ? <X> : ();
   }

   {
      my $path = $self->{path};
      do {
         $data->{top} ||= read_file "$path.dols/top";
         $data->{bot} ||= read_file "$path.dols/bot";
         $path =~ s/[^\/]*\/+$//
            or die "malformed path: $path";
      } while $path ne "";
   }

   local *DIR;
   if (opendir DIR, $self->{path}) {
      my $dlen = 0;
      my $flen = 0;
      my $slen = 0;
      for (sort readdir DIR) {
         next if /$ignore/;
         stat "$self->{path}$_";
         if (-d _) {
            next unless 0555 == ((stat _)[2] & 0555);
            $dlen = length $_ if length $_ > $dlen;
            push @{$data->{d}}, $_;
         } else {
            next unless 0444 == ((stat _)[2] & 0444);
            my $s = -s _;
            $flen = length $_ if length $_ > $dlen;
            $slen = length $s if length $s > $dlen;
            push @{$data->{f}}, [$_, $s];
         }
      }
      $data->{dlen} = $dlen;
      $data->{flen} = $flen;
      $data->{slen} = $slen;
   }

   $data;
}

sub conn::get_statdata {
   my $self = shift;

   my $mtime = $self->{stat}[9];

   $statdata = $diridx{$self->{path}};

   if (defined $statdata) {
      $$statdata = Storable::thaw $statdata;
      return $$statdata
         if $$statdata->{version} == $SD_VERSION
            && $$statdata->{mtime} == $mtime;
   }

   $self->slog(8, "creating index cache for $self->{path}");

   $$statdata = $self->gen_statdata;
   $$statdata->{version} = $SD_VERSION;
   $$statdata->{mtime}   = $mtime;

   $diridx{$self->{path}} = Storable::freeze $$statdata;
   (tied %diridx)->db_sync;

   $$statdata;
}

sub handle_redirect { # unused
   if (-f ".redirect") {
      if (open R, "<.redirect") {
         while (<R>) {
            if (/^(?:$host$port)$uri([^ \tr\n]*)[ \t\r\n]+(.*)$/) {
               my $rem = $1;
               my $url = $2;
               print $nph ? "HTTP/1.0 302 Moved\n" : "Status: 302 Moved\n";
               print <<EOF;
Location: $url
Content-Type: text/html

<html>
<head><title>Page Redirection to $url</title></head>
<meta http-equiv="refresh" content="0;URL=$url">
</head>
<body text="black" link="#1010C0" vlink="#101080" alink="red" bgcolor="white">
<large>
This page has moved to $url.<br />
<a href="$url">
The automatic redirection has failed. Please try a <i>slightly</i>
newer browser next time, and in the meantime <i>please</i> follow this link ;)
</a>
</large>
</body>
</html>
EOF
            }
         }
      }
   }
}

sub format_time {
   if ($_[0] < 0) {
      "--:--:--";
   } elsif ($_[0] >= 60*60*24) {
      sprintf "%02dd&#160;%02d:%02d:%02d",
              int ($_[0] / (60 * 60 * 24)),
              int ($_[0] / (60 * 60)) % 24,
              int ($_[0] / 60) % 60,
              int ($_[0]) % 60;
   } else {
      sprintf "%02d:%02d:%02d",
              int ($_[0] / (60 * 60)) % 24,
              int ($_[0] / 60) % 60,
              int ($_[0]) % 60;
   }
}

sub conn::diridx {
   my $self = shift;

   my $data = $self->get_statdata;

   my $stat;
   if ($data->{dlen}) {
      $stat .= "<table><tr><th>Directories</th></tr>";
      $data->{dlen} += 1;
      my $cols = int ((79 + $data->{dlen}) / $data->{dlen});
      $cols = @{$data->{d}} if @{$data->{d}} < $cols;
      my $col = $cols;
      for (@{$data->{d}}) {
         if (++$col >= $cols) {
            $stat .= "<tr>";
            $col = 0;
         }
         if ("$self->{path}$_" =~ $conn::blockuri{$self->{country}}) {
            $stat .= "<td>$_ ";
         } else {
            $stat .= "<td><a href='".escape_uri("$_/")."'>$_</a> ";
         }
      }
      $stat .= "</table>";
   }
   if ($data->{flen}) {
      $data->{flen} += 1 + $data->{slen} + 1 + 3;
      my $cols = int ((79 + $data->{flen}) / $data->{flen});
      $cols = @{$data->{f}} if @{$data->{f}} < $cols;
      my $col = $cols;
      $stat .= "<table><tr>". ("<th align='left'>File<th>Size<th>&nbsp;" x $cols);
      for (@{$data->{f}}) {
         if (++$col >= $cols) {
            $stat .= "<tr>";
            $col = 0;
         }
         $stat .= "<td><a href='".escape_uri($_->[0])."'>$_->[0]</a><td align='right'>$_->[1]<td>&nbsp;";
      }
      $stat .= "</table>";
   }

   <<EOF;
<html>
<head><title>$self->{uri}</title></head>
<body bgcolor="#ffffff" text="#000000" link="#0000ff" vlink="#000080" alink="#ff0000">
<h1>$data->{path}</h1>
$data->{top}
<hr />
<a href="/internal/status">Server Status Page &amp; Queueing Info</a>
<hr />
$stat
$data->{bot}
</body>
</html>
EOF
}

sub statuspage {
   my ($self, $verbose) = @_;

   my $uptime = format_time ($::NOW - $::starttime);
   
   my $content = <<EOF;
<html>
<head><title>Server Status Page</title></head>
<body bgcolor="#ffffff" text="#000000" link="#0000ff" vlink="#000080" alink="#ff0000">
<h1>Server Status Page</h1>
<h2>Myhttpd</h2>
version <b>$VERSION</b>; current:max connection count: <b>$::conns</b>:<b>$::maxconns</b>; uptime: <b>$uptime</b>;<br />
client-id <b>$self->{remote_id}</b>; client country <b>$self->{country}</b>;<br />
<h2>Queue Statistics</h2>
<ul>
EOF

   for (
         ["download queue", $queue_file],
         ["other queue",    $queue_index],
   ) {
      my ($name, $queue) = @$_;
      my @waiters = $queue->waiters;
      $waiters[$_]{idx} = $_ + 1 for 0..$#waiters;

      if (@waiters) {
         $content .= "<li>$name<br />".(scalar @waiters)." client(s); $queue->{started} downloads started;";
         
         $content .= "<p>Waiting time until download starts, estimated:<ul>";
         for (
               ["by most recently started transfer", $queue->{lastspb}],
               ["by queue average", $queue->{avgspb}],
               ["by next client in queue", $waiters[0]{spb}],
         ) {
            my ($by, $spb) = @$_;
            $content .= "<li>$by<br />";
            if ($spb) {
               $content .= sprintf "100 KB file: <b>%s</b>; 1 MB file: <b>%s</b>; 100MB file: <b>%s</b>;",
                                   format_time($spb*    100_000),
                                   format_time($spb*  1_000_000),
                                   format_time($spb*100_000_000);
            } else {
               $content .= "(unavailable)";
            }
            $content .= "</li>";
         }
         $content .= "</ul></p>";

         @waiters = grep { $verbose || $_->{coro}{conn}{remote_id} eq $self->{remote_id} } @waiters;
         if (@waiters) {
            $content .= "<table border='1' width='100%'><tr><th>#</th><th>Remote ID</th>".
                        "<th>CN</th><th>Size</th><th>Waiting</th><th>ETA</th><th>URI</th></tr>";
            for (@waiters) {
               my $conn = $_->{coro}{conn};
               my $time = format_time ($::NOW - $_->{time});
               my $eta  = $queue->{avgspb} * $_->{size} - ($::NOW - $_->{time});

               $content .= "<tr>".
                           "<td align='right'>$_->{idx}</td>".
                           "<td>$conn->{remote_id}</td>".
                           "<td>$conn->{country}</td>".
                           "<td align='right'>$_->{size}</td>".
                           "<td align='right'>$time</td>".
                           "<td align='right'>".($eta < 0 ? "<font color='red'>overdue</font>" : format_time $eta)."</td>".
                           "<td>".escape_html($conn->{name})."</td>".
                           "</tr>";
            }
            $content .= "</table></li>";
         }
         $content .= "</li>";
      } else {
         $content .= "<li>$name<br />(empty)</li>";
      }
   }

   $content .= <<EOF;
</ul>
</body>
</html>
EOF

   $self->response(200, "ok",
         {
            "Content-Type"   => "text/html",
            "Content-Length" => length $content,
         },
         $content);
};

$::internal{status} = sub { statuspage($_[0], 0) };
$::internal{queue}  = sub { statuspage($_[0], 1) };

1;
