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
         next unless -r _;
         if (-d _) {
            $dlen = length $_ if length $_ > $dlen;
            push @{$data->{d}}, $_;
         } else {
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

sub conn::diridx {
   my $self = shift;

   my $data = $self->get_statdata;

   my $uptime = int (time - $::starttime);
   $uptime = sprintf "%02dd %02d:%02d",
                     int ($uptime / (60 * 60 * 24)),
                     int ($uptime / (60 * 60)) % 24,
                     int ($uptime / 60) % 60;
   
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

   my $waiters = sprintf "%d/%d", $::transfers[0][0]->waiters+0, $::transfers[1][0]->waiters+0;
   my $avgtime = sprintf "%d/%d second(s)", $::transfers[0][1], $::transfers[1][1];

   <<EOF;
<html>
<head><title>$self->{uri}</title></head>
<body bgcolor="#ffffff" text="#000000" link="#0000ff" vlink="#000080" alink="#ff0000">
<h1>$data->{path}</h1>
$data->{top}
<small><div align="right">
         <tt>$self->{remote_id}/$self->{country} - $::conns connection(s) - uptime $uptime - myhttpd/$VERSION
</tt></div></small>
<hr />
clients waiting for data transfer: $waiters<br />
average waiting time until transfer starts: $avgtime <small>(adjust your timeout values)</small><br />
<hr />
$stat
$data->{bot}
</body>
</html>
EOF
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

1;
