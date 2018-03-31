#!/usr/bin/env ruby
require 'logger'
require 'rubygems'
require 'json'
require 'fileutils'

# cmd.exe /c start /min ruby C:\Users\Hunters\Videos\scripts\extractFilestoDir.rb "%D" "%N" COMMAND ^& exit
# %D - directory
# %N - name of file as matched in .json
# ---------------------------------------------------------------------
# SETUP - MODIFY THESE AS REQUIRED
# ---------------------------------------------------------------------

$log = Logger.new( "#{File.dirname(__FILE__)}\\extractFilestoDir.log", 'monthly' )
settings_file = "#{File.dirname(__FILE__)}\\extract_and_move_settings.json"
settings_hash = JSON.parse(File.read(settings_file))

# get our subset of just the default
default_files_to_keep = settings_hash['default_settings']['destinations'][0]['filestokeep']
default_torrent_dir = settings_hash['default_settings']['destinations'][0]['path']

# Set 7Zip path
$zip = 'c:\apps\7-Zip\7Z.exe'
#convert command
$convert = 'C:\apps\ffmpeg\bin\ffmpeg'

# ---------------------------------------------------------------------
# DO NOT MODIFY BELOW THIS LINE
# ---------------------------------------------------------------------
def unzip(torrent_directory, destination)
  Dir.chdir("#{torrent_directory}")
  # give me a list of the rar and zip files
  zipfiles = Dir.glob("**/*.{rar,zip}")
  zipfiles.reverse.each do |f|
    cmd = "#{$zip} e -o\"#{destination}\" \"#{f}\" -aoa"
    system cmd
    if $?
      $log.info "Extracted: #{f} into #{destination}"
    else
      $log.error "Not deleting #{f} because the conversion failed"
    end
  end
end

def delete_file(thefile)
  begin
    File.delete(thefile) if File.exist?(thefile)
  rescue => e
    $log.error "delete of #{thefile} failed #{e.message} #{e.backtrace}"
  end
end

def copy_converted_files(hash_files, destination)
  Dir.chdir(destination)
  hash_files['delete'].each do |f|
    delete_file(f)
  end
  hash_files['converted'].each do |f|
    FileUtils.cp(f, destination)
    $log.info "Copied: #{f} into #{destination}"
  end
end

def post_process_extracts(directory)
  converted_files = Hash.new
  converted_files['delete'] = Array.new
  converted_files['converted'] = Array.new
  Dir.chdir("#{directory}")
  files = (Dir.glob "*.{mkv,avi,mpg}")
  files.each do |f|
    $log.info "Converting file: #{f}"
    file_basename = File.basename(f, '.*')
    cmd = "#{$convert} -y -i \"#{f}\"" +
      " -vcodec libx264 -acodec aac -ac 2 -ab 160k -strict -2" +
      " -loglevel warning" +
      " \"#{directory}\\#{file_basename}.mp4\""
    # convert it unless the file already exists for some reason, why waste?
    system cmd unless File.exist?("#{directory}\\#{file_basename}.mp4")
    if $?
      delete_file(f)
    else
      $log.error "Not deleting #{f} because the conversion failed"
    end
    converted_files['delete'].push (f)
    converted_files['converted'].push ("#{directory}\\#{file_basename}.mp4")
  end
  # possibly no files to convert, but we want to move them anyway...
  if (files.count == 0)
     files = (Dir.glob "*.*")
     files.each do |f|
       # check the dates to see if its modified time is < 1 day
       # assuming the modified time gets modified when we unzip?
       daysold = (Time.now - File.stat(f).mtime).to_i / 86400.0
       if (daysold < 1)
         # add to the converted array so we know to copy it later
         converted_files['converted'].push ("#{directory}\\#{f}")
       end
     end
  end
  return converted_files
end

def extractFiles(torrent_directory, destinations, title)
  hash_of_files = Hash.new
  destinations.each do |destination|
    # create the destination if it doesnt exist
    if File.directory?(destination)
      puts "creating mtime #{Time.new} on #{destination}"
      File.utime(Time.new, File.atime(destination), destination)
    else
      FileUtils::mkdir_p(destination)
    end
    if hash_of_files.length > 0
      # if we have previously converted files
      copy_converted_files(hash_of_files, destination)
    else
      unzip(torrent_directory, destination)
      # we need to convert files
      hash_of_files = post_process_extracts(destination)
    end
  end
end

def delfiles(destination, maxfilecount)
  dir_files = []
  dir_files = Dir.glob("*.{mkv,avi,mpg,mp4}").sort_by { |x| File.ctime(x) }
  dir_files[0..dir_files.count-maxfilecount].each_index{|i|
    $log.info "deleting #{destination}\\#{dir_files[i]} since there are #{dir_files.count} files and only allowed #{maxfilecount}"
    delete_file("#{destination}\\#{dir_files[i]}")
  }

end

def cleanup(destination, maxfilecount)
  begin
    Dir.chdir("#{destination}")
    curfilecount = (Dir.glob "*.{mkv,avi,mpg,mp4}").count
    if curfilecount > maxfilecount
      $log.info "deleting files from #{destination}"
      delfiles(destination, maxfilecount)
    else
      $log.info "#{curfilecount} files in #{destination}"
    end
  rescue Errno::ENOENT => e
    $log.error "#{destination} doesnt exist #{e.message}"
  end
end

# this is our main
if (ARGV.length < 2)
  print 'Enter the TorrentDir: '
  torrentDir = gets.chomp
  print 'Enter the torrentTitle: '
  torrentTitle = gets.chomp
else
  # Get directory of zip to extract from arguments
  torrentDir = ARGV[0]
  # Get filename from arguments
  torrentTitle = ARGV[1]
end

# throw some crap in the log
$log.info "Start: Using path and title:  #{torrentDir} #{torrentTitle}"

# note this only finds the first match in our settings, hopefully we are specific
item_match = settings_hash.select { |key, _| torrentTitle.downcase.include? key.downcase }
if (item_match.count > 0)
  $log.info "Found #{item_match.count} matching torrent(s) #{item_match}"
  if (item_match.count > 1)
    $log.info "Bad things, your settings need to be reworked to find uniqueness, I'm prob broken like this"
  end
  paths = Hash.new
  item_match.each do |key, value|
    item_match[key]['destinations'].each do |destination|
      paths["#{destination['path']}"] = destination['filestokeep']
      unless destination['filestokeep'].nil?
        cleanup(destination['path'],destination['filestokeep'])
      end
    end
  end
  # we only want the keys as an array to pass to extract files
  extractFiles(torrentDir, paths.keys, torrentTitle)
else
  $log.info "No match found, extracting into #{torrentDir}"
  extractFiles(torrentDir, torrentDir.split(','), torrentTitle)
end
$log.info "complete #{torrentDir} and title: #{torrentTitle}"
