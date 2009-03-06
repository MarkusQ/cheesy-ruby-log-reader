require 'net/smtp'

$= = TRUE  # Hashes are case-insensitive

def grep(pattern,options='')
    options += ' -i'         if pattern.is_a? Regexp and pattern.casefold?
    pattern = pattern.source if pattern.is_a? Regexp
    pattern = pattern.gsub(/\\s/,"[\ ]").gsub(/\*/,"\*")
    `egrep #{options} "#{pattern}" #{$current_file}`
    end

def count(pat,options='')
    grep pat, options+" -c"
    end

def in_log(file)
    $current_file = file
    ''
    end

def rank(pat,format="\n\t    #item #times times.")
    return rank(pat,format) {|l| $1 if l =~ pat } unless block_given?
    totals = Hash.new(0)
    grep(pat).split("\n").each { |l| totals[yield(l)] += 1 }
    (totals.sort { |a,b| b[1]<=>a[1] }).collect { |item,times|
        format.gsub('#item',item).gsub('#times',times.to_s) if item
        }.compact
    end

def rank_and_instances(pat)
    totals = Hash.new(0)
    grep(pat).split("\n").each { |l| totals[(l =~ pat) ? $1 : nil] += 1 }
    (totals.sort { |a,b| b[1]<=>a[1] }).collect { |item,times| yield(pat,item,times) if item }.compact
    end

def list_instances(pat,item)
    grep(pat).
        split("\n").
        delete_if { |l| not (l =~ pat and $1 == item) }.
        collect { |l| "\n\t        "+l }.
        join('')
    end

def tell(who,msg)
    last = -1
    msg = msg.split("\n").collect{ |l|
        case l
            when /^\t/ then l.sub(/^\t/," "*last)
            when /\S/  then last = l =~ /\S/; l
            else            (" "*last)+'#' if last >= 0
            end
        }.compact
    indent = msg.collect { |l| (l =~ /\S/) or 0 }.min
    msg.collect! { |l| l[indent..-1]}
    #msg.each { |l| print l,"\n" }
    msg.unshift ""
    msg.unshift "Subject: "+msg[1]
    Net::SMTP.start('localhost') { |mail_server| mail_server.send_mail(msg.join("\n"),'you@yourdomain.com',who) }
    end

$yesterday = (Time.now - 60*60*24).strftime('%b %d').gsub(/ 0/,'  ')
$date_pattern = (ARGV.length > 0) ? ARRG[0] : $yesterday

def prefix(p,b)
    b = b.split("\n") if b.is_a? String
    p + (b.join("\n"+p))
    end

class String
    def able_to_add(line)
        FALSE
        end
    end

class Object
    def replicate
        clone
        end
    end

class Array
    def replicate
        collect { |i| i.replicate }
        end
    end

class Hash
    def replicate
        result = {}
        each_key { |k| result[k] = self[k].replicate }
        result
        end
    end

class A_basic_bucket
    attr_accessor :name
    def initialize
        @name = ''
        end
    def able_to_add(line)
        FALSE
        end
    def contents
        []
        end
    def to_s
        details = self.contents.delete_if { |l| l.length == 0 }.join("\n")
        return details if @name == '' or details == ''
        details = (details.length > 20) ? ("\n"+prefix("    ",details)) :details.gsub(/\n\s*/,', ')
        (@name + ": " + details).gsub(/:\s*\n?\s*\(\^\)/,' ').gsub("\n\s*\n","\n").chomp
        end
    def called(s)
        @name = s #+ ' '
        self
        end
    def weight
        1
        end
    end

class A_bucket < A_basic_bucket
    attr_accessor :max_instances, :instances, :count
    def initialize(n)
        super()
        @max_instances = n
        @count = 0
        @instances = []
        end
    def able_to_add(line)
        @count += 1
        @instances << line if @count <= @max_instances and line =~ /\S/
        TRUE
        end
    def to_s_x
        return '' if @max_instances < 0 or @count == 0
        result = @name + " " + @count.to_s + " times"
        return result if @instances.length == 0
        return result + ":\n" + prefix("    ",@instances) if @count == @instances.length
        result + " ("+@instances.length.to_s+" listed):\n" + prefix("",@instances)
        end
    def contents
        return [] if @max_instances < 0 or @count == 0
        result = "(^)" + @count.to_s + " times"
        return [result] if @instances.length == 0
        return [result] + @instances if @count == @instances.length
        [result + " ("+@instances.length.to_s+" listed):"] + @instances
        end
    def replicate
        result = super
        result.instances = @instances.replicate
        result
        end
    def weight
        @count
        end
    end

class A_bucket_brigade < A_basic_bucket
    attr_accessor :pattern, :buckets, :weight_cache
    def initialize(pat,buckets)
        super()
        @pattern  = pat
        @buckets  = buckets + [itemize(10).called('~others~')]
        @name = @pattern.source.chomp
        end
    def able_to_add(line)
        return FALSE unless line =~ @pattern
        @weight_cache = nil
        line = $` + $'
        @buckets.each { |b| return TRUE if b.able_to_add(line) }
        return FALSE
        end
    def contents
        @buckets.collect { |b| b.to_s }
        end
    def replicate
        result = super
        result.buckets = @buckets.replicate
        result
        end
    def weight
        return @weight_cache if @weight_cache
        t = 0
        @buckets.each { |b| t += b.weight }
        @weight_cache = t
        end
    end

Max_max_instances = 99999
class A_bucket_cascade < A_basic_bucket
    attr_accessor :pattern, :buckets, :min_weight, :max_instances, :weight_cache
    def initialize(pat,buckets)
        super()
        @pattern  = pat
        @buckets  = buckets
        @buckets.each { |k,v| v.called(k.to_s) if v.is_a? A_basic_bucket and v.name == '' }
        @name = @pattern.source
        @min_weight = 0
        @max_instances = Max_max_instances
        end
    def copy_of_default_for(key)
        result = @buckets[:default].replicate
        result.called(key) if result.is_a? A_basic_bucket
        result
        end
    def able_to_add(line)
        return FALSE unless line =~ @pattern
        @weight_cache = nil
        key = $1
        line = $` + $'
        if      @buckets.has_key? key       then #fine, use it
          elsif @buckets.has_key? :others   then key = :others
          elsif @buckets.has_key? :default  then @buckets[key] = copy_of_default_for(key)
          else                                   return FALSE
          end
        @buckets[key] = A_bucket_brigade.new( //, @buckets[key]).called(key.to_s) if @buckets[key].is_a? Array
        return @buckets[key].able_to_add(line)
        end
    def contents
        @buckets.delete :default
        #@buckets.delete_if { |k,v| v.is_a? Array }
        n = 0
        if @max_instances == Max_max_instances and @min_weight == 0
            @buckets.sort.collect { |k,v| v.to_s }
          elsif @max_instances == Max_max_instances
            @buckets.sort.collect { |k,v| v.to_s if v.weight > @min_weight}.compact
          else
            @buckets.sort { |a,b| b[1].weight <=> a[1].weight }.collect { |k,v|
                (n += 1; v.to_s) if n < @max_instances and v.weight > @min_weight
                }.compact
          end
        end
    def replicate
        result = super
        result.buckets = @buckets.replicate
        result
        end
    def weight
        return @weight_cache if @weight_cache
        t = 0
        @buckets.each { |k,b| t += b.weight }
        @weight_cache = t
        end
    end

def in_log_file(file_names,break_down)
    file_names = [file_names] if file_names.is_a? String
    file_names.each { |file_name| File.foreach(file_name) { |l| break_down.able_to_add(l.chomp) } }
    prefix("\t",break_down.to_s)[1..-1]
    end

def lines_matching(pat,*sub_buckets)
    A_bucket_brigade.new(pat,sub_buckets)
    end

def group_by(pat,sub_buckets={})
    sub_buckets[:default] = count unless sub_buckets.has_key? :default
    A_bucket_cascade.new(pat,sub_buckets)
    end

def top(n,pat,sub_buckets={})
    sub_buckets[:default] = count unless sub_buckets.has_key? :default
    result = A_bucket_cascade.new(pat,sub_buckets)
    result.max_instances = n
    result
    end

def weight_over(n,pat,sub_buckets={})
    sub_buckets[:default] = count unless sub_buckets.has_key? :default
    result = A_bucket_cascade.new(pat,sub_buckets)
    result.min_weight = n
    result
    end

def itemize(max_number=999)
    A_bucket.new(max_number)
    end

def count
    A_bucket.new(0)
    end

def ignore
    A_bucket.new(-1)
    end

#----------------------------------------------------------------------------------------------------------


    tell ["you@yourdomain.com"], %Q{
        Log monitor for #{$date_pattern}

        From messages:
        #{in_log_file( ['/var/log/messages','/var/log/secure', '/var/log/maillog'],
            lines_matching( /#{$date_pattern}/,
                group_by( /#{`hostname -s`.chomp} ([\w\-\.]+).*?:/,
                    'named' => [
                        lines_matching(/lame server/, count),
                        ],
                    'ftpd' => [
                        group_by( /USER (.*) timed out after 300 seconds .*/ ).called('Timeouts'),
                        group_by( /USER (.*)/ ).called('Users'),
                        lines_matching(/PASS/,count).called('Passwords given'),
                        lines_matching( /FTP LOGIN FROM (.*)/,count).called('Login'),
                        group_by( /CWD (.*)/).called('Directory changes'),
                        lines_matching(/PORT|TYPE/,count).called('Misc session commands'),
                        lines_matching(/NLST/,count).called('Directories listed'),
                        lines_matching(/STOR/,count).called('Files uploaded'),
                        lines_matching(/RETR/,count).called('Files downloaded'),
                        lines_matching(/DELE/,count).called('Files deleted'),
                        lines_matching(/RNFR|RNTO/,count).called('Files renamed (from + to)'),
                        lines_matching(/QUIT/,count),
                        lines_matching(/FTP session closed/,count),
                        lines_matching(/lost connection to (.*)/,count),
                        ],
                    'su' => [
                        group_by( /for user (\w+)/ ),
                        ],
                    'sudo' => [
                        lines_matching(/authentication failure/, itemize),
                        ],
                    'ipop3d' => [
                        lines_matching(/service init/,count).called('Service started'),
                        group_by(/Login user=(\S*)/).called('Logins'),
                        group_by(/Logout user=(\S*)/).called('Logouts'),
                        group_by(/Auth user=(\S*)/).called('Authorizations'),
                        itemize(10)
                        ],
                    'logger' => top(50,/spamtrapped(.*)/).called('Spamtrapped (top 50)'),
                    'postfix' => [
                        top(0,/disconnect from (.*)\[/).called(''),
                        top(25,/connect from (.*)\[/).called('Connections (top 25)'),
                        top(25,/from=\<(.*)\>/).called('Mail from (top 25)'),
                        top(25,/to=\<(.*)\>/).called('Mail to (top 25)'),
                        top(0,/client=/).called(''),
                        top(0,/message-id=/).called(''),
                        lines_matching(/lookup table has changed/).called('Lookup table has changed'),
                        group_by(/connect to (.*): Connection timed out (port 25)/).called('Timeouts')
                        group_by(/warning: (\S*: hostname \S*) verification failed: Host not found.*/)
                        ],
                    :default => itemize(10)
                    ).called('Service')
                ).called('Service logs')
            )}

        From apache error log:
        #{in_log_file( '/var/log/httpd/error_log',
            lines_matching( /\[... #{$yesterday} \d\d:\d\d:\d\d\d\d\d\d\]/,
                group_by( / \[(.+?)\]/,
                    'error' => [
                        group_by( /\[client.+?\] (.+?)(:|$)/,
                            'File does not exist' =>
                                  group_by( /\/var\/www\/html\/(.+?)\//,
                                      :default => group_by( / (.*)/)).called('File does not exist'),
                            :default => itemize(10).called('Other client errors')
                            ).called('Client errors'),
                        itemize.called('System errors')
                        ],
                    'info'   => [
                        lines_matching(/Fixed case: ....NEWS.*/,count).called('Newsletter capitalization'),
                        group_by( /\[client.+?\] (.+)/,
                            :default => itemize(100)
                            ).called('misc')
                        ],
                    'notice' => itemize.called('Notices'),
                    :default => itemize(10).called('Other messages')
                    ).called('(^)')
                 ).called('Web server messages')
            )}
        }

