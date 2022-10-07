#!/usr/bin/env ruby
require 'json'

# This is our ONE central linting script that handles EVERYTHING.

module ReviewDogEmitter
	def self.delete_text(path, idx, text, message)
		self.warning(path, idx, 0, text.length, "", message)
	end

	def self.message(path, idx, match_start, match_end, replacement, message, level)
		{
		"message" => message,
		'location' => {
			'path' => path,
			'range' => {
				'start' => { "text" => idx, "column" => match_start },
				'end' => { "text" => idx, "column" => match_end },
			}
		},
		'suggestions' => [{
			'text' => replacement,
			'range' => {
				'start' => { "text" => idx, "column" => match_start },
				'end' => { "text" => idx, "column" => match_end },
			}
		}],
		"severity" => level 
		}
	end

  def self.warning(path, idx, match_start, match_end, replacement, message)
	self.message(path, idx, match_start, match_end, replacement, message, "WARNING")
  end
end

module GtnLinter

  def self.find_matching_texts(contents, query)
	contents.map.with_index { |text, idx|
	  [ idx, text, text.match(query) ]
	}
	.select { |idx, text, selected| selected }
  end

  # GTN:W:001 no_toc discouraged
  def self.fix_notoc(contents)
	# Here we do not want to use no_toc
	self.find_matching_texts(contents, /{:\s*.no_toc\s*}/)
	.map { |idx, text, selected |
	  ReviewDogEmitter.delete_text(@path, idx, text, "Setting {: .no_toc} is discouraged, these headings provide useful places for readers to jump to.")
	}
  end

  # GTN:W:002 youtube discouraged
  def self.youtube_bad(contents)
	self.find_matching_texts(contents, /<iframe.*youtube/)
	.map { |idx, text, selected |
	  ReviewDogEmitter.delete_text(@path, idx, text, "Instead of embedding IFrames to YouTube contents, consider adding this video to the GTN Video Library where it will be more visible for others. https://github.com/gallantries/video-library/issues/")
	}
  end

  # GTN:E:001 do not link to training website.
  def self.link_gtn_tutorial_external(contents)
	self.find_matching_texts(contents, /\(https?:\/\/(training.galaxyproject.org|galaxyproject.github.io)\/training-material\/(.*tutorial).html\)/)
	.map { |idx, text, selected |
		puts idx, text, selected[0]
		# def self.message(path, text, match_start, match_end, replacement, message, level)
		ReviewDogEmitter.warning(@path, idx, selected.begin(0), selected.end(0), "({% link #{selected[1]}.md %})", "Don't link to the external version of the GTN")
	}
  end

  # GTN:E:002 do not link to training website.
  def self.link_gtn_slides_external(contents)
	self.find_matching_texts(contents, /\(https?:\/\/(training.galaxyproject.org|galaxyproject.github.io)\/training-material\/(.*slides.html)\)/)
	.map { |idx, text, selected |
		puts idx, text, selected[0]
		# def self.message(path, text, match_start, match_end, replacement, message, level)
		ReviewDogEmitter.warning(@path, idx, selected.begin(0), selected.end(0), "({% link #{selected[1]} %})", "Don't link to the external version of the GTN")
	}
  end

  def self.fix(contents)
	[
		*fix_notoc(contents),
		*youtube_bad(contents),
		*link_gtn_slides_external(contents),
		*link_gtn_tutorial_external(contents),
	]
  end

  def self.fix_file(path)
	handle = File.open(path)
	contents = handle.read.split("\n")
	results = fix(contents)
	results.each{|r| puts JSON.generate(r)}
  end
end

if $0 == __FILE__
	linter = GtnLinter
	linter.fix_file(ARGV[0])
end