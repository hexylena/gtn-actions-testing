#!/usr/bin/env ruby
require 'bibtex'
require 'json'

# This is our ONE central linting script that handles EVERYTHING.

module ReviewDogEmitter
	def self.delete_text(path, idx, text, message)
		self.warning(path, idx, 0, text.length, "", message)
	end

	def self.message(path, idx, match_start, match_end, replacement, message, level)
		res = {
			"message" => message,
			'location' => {
				'path' => path,
				'range' => {
					'start' => { "line" => idx + 1, "column" => match_start },
					'end' => { "line" => idx + 1, "column" => match_end },
				}
			},
			"severity" => level 
		}
		if ! replacement.nil? 
			res['suggestions'] = [{
				'text' => replacement,
				'range' => {
					'start' => { "line" => idx + 1, "column" => match_start },
					'end' => { "line" => idx + 1, "column" => match_end },
				}
			}]
		end
		res
	end

  def self.warning(path, idx, match_start, match_end, replacement=nil, message)
	self.message(path, idx, match_start, match_end, replacement, message, "WARNING")
  end
end

module GtnLinter
	@BAD_TOOL_LINK = /{% tool (\[[^\]]*\])\(https?.*tool_id=([^)]*)\)\s*%}/i

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
		# def self.message(path, text, match_start, match_end, replacement, message, level)
		ReviewDogEmitter.warning(@path, idx, selected.begin(0), selected.end(0), "({% link #{selected[2]}.md %})", "Don't link to the external version of the GTN")
	}
  end

  # GTN:E:002 do not link to training website.
  def self.link_gtn_slides_external(contents)
	self.find_matching_texts(contents, /\(https?:\/\/(training.galaxyproject.org|galaxyproject.github.io)\/training-material\/(.*slides.html)\)/)
	.map { |idx, text, selected |
		# def self.message(path, text, match_start, match_end, replacement, message, level)
		ReviewDogEmitter.warning(@path, idx, selected.begin(0), selected.end(0), "({% link #{selected[2]} %})", "Don't link to the external version of the GTN")
	}
  end

  # GTN:E:003 use citations rather than doi links
  def self.check_dois(contents)
	self.find_matching_texts(contents, /\]\(https?:\/\/doi.org\/10.[^5][^2][^8][^1][^\)]*\)/)
	.map { |idx, text, selected |
		# def self.message(path, text, match_start, match_end, replacement, message, level)
		ReviewDogEmitter.warning(@path, idx, selected.begin(0), selected.end(0), "]({% cite ... %})", "This looks like a DOI which could be better served by using the built-in Citations mechanism. You can use https://doi2bib.org to convert your DOI into a .bib formatted entry, and add to your tutorial.md")
	}
  end

  # GTN:E:004 useless link text
  def self.check_bad_link_text(contents)
	self.find_matching_texts(contents, /\[\s*here\s*\]/i)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(0), selected.end(0),
			"[Something better here]", 
			"Do not use 'here' as your link title, it is " +
			"[bad for accessibility](https://usability.yale.edu/web-accessibility/articles/links#link-text). " +
			"Instead try restructuring your sentence to have useful descriptive text in the link."
		)
	}
  end

  # GTN:E:005 incorrect jekyll function calls
  def self.incorrect_calls(contents)
	a = self.find_matching_texts(contents, /([^{]|^)(%\s*[^%]*%})/i)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(2), selected.end(2),
			"{#{selected[2]}", 
			"It looks like you might be missing the opening { of a jekyll function"
		)
	}
	b = self.find_matching_texts(contents, /{([^%]\s*[^%]* %})/i)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(1), selected.end(1),
			"{%#{selected[1]}", 
			"It looks like you might be missing the opening % of a jekyll function"
		)
	}


	c = self.find_matching_texts(contents, /({%\s*[^%]*%)([^}]|$)/i)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(2), selected.end(2),
			"#{selected[1]}}#{selected[2]}", 
			"It looks like you might be missing the closing } of a jekyll function"
		)
	}

	d = self.find_matching_texts(contents, /({%\s*[^}]*[^%])}/i)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(1), selected.end(1),
			"#{selected[1]}%}", 
			"It looks like you might be missing the closing % of a jekyll function"
		)
	}
	a + b + c + d
  end

  # GTN:E:006 References non-existent snippet
  def self.non_existent_snippet(contents)
	self.find_matching_texts(contents, /{%\s*snippet\s+([^ ]*)/i)
	.select { |idx, text, selected |
		! File.exists?(selected[1])
  	}
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(0), selected.end(0),
			nil,
			"This snippet does not seem to exist"
		)
	}
  end

  # GTN:E:007 Bad tool link
  def self.bad_tool_links(contents)
	self.find_matching_texts(contents, @BAD_TOOL_LINK)
	.map { |idx, text, selected |
		ReviewDogEmitter.warning(
			@path, idx, selected.begin(0), selected.end(0),
			"{% tool #{selected[1]}(#{selected[2]}) %}",
			"You have used the full tool URL to a specific server, here we only need the tool ID portion."
		)
	}
  end

  # GTN:W:008 Used TestToolShed Links


  def self.fix_md(contents)
	[
		*fix_notoc(contents),
		*youtube_bad(contents),
		*link_gtn_slides_external(contents),
		*link_gtn_tutorial_external(contents),
		*check_dois(contents),
		*check_bad_link_text(contents),
		*incorrect_calls(contents),
		*non_existent_snippet(contents),
		*bad_tool_links(contents),
	]
  end

  def self.bib_missing_mandatory_fields(bib)
	results = []
	for x in bib
		begin
			doi = x.doi
		rescue
			doi = nil
		end

		begin
			url = x.url
		rescue
			url = nil
		end

		if doi.nil? && url.nil?
			results.push([x.key, "Missing both a DOI and a URL. Please add one of the two."])
		end

		begin
			x.title
			if ! x.title
				results.push([x.key, "This entry is missing a title attribute. Please add it."])
			end
		rescue
			results.push([x.key, "This entry is missing a title attribute. Please add it."])
		end
	end
	return results
  end

  def self.fix_bib(contents, bib)
	bad_keys = bib_missing_mandatory_fields(bib)
	results = []
	bad_keys.each{|key, reason|
		results += self.find_matching_texts(contents, /^\s*@.*{#{key},/)
		.map { |idx, text, selected |
			ReviewDogEmitter.warning(
				@path, idx, 0, text.length, nil,
				reason
			)
		}
	}
	results
  end

  def self.fix_file(path)
	@path = path

	if path.match(/md$/)
		handle = File.open(path)
		contents = handle.read.split("\n")
		results = fix_md(contents)
		results.each{|r| puts JSON.generate(r)}
	elsif path.match(/.bib$/)
		handle = File.open(path)
		contents = handle.read.split("\n")

		bib = BibTeX.open(path)
		results = fix_bib(contents, bib)
		results.each{|r| puts JSON.generate(r)}
	end
  end
end

if $0 == __FILE__
	linter = GtnLinter
	linter.fix_file(ARGV[0])
end