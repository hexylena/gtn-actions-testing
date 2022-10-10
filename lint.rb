#!/usr/bin/env ruby
require 'bibtex'
require 'json'

# This is our ONE central linting script that handles EVERYTHING.

module ReviewDogEmitter

  @CODE_URL = "https://github.com/galaxyproject/training-material/wiki/"
  def self.delete_text(path: "", idx: 0, text: "", message: "No message", code: "GTN000", full_line: "")
    self.error(
      path: path,
      idx: idx,
      match_start: 0,
      match_end: text.length, 
      replacement: "", 
      message: message, 
      code: code,
      full_line: full_line,
    )
  end

  def self.warning(path: "", idx: 0, match_start: 0, match_end: 1, replacement: nil, message: "No message", code: "GTN000", full_line: "")
    self.message(
      path: path,
      idx: idx,
      match_start: match_start, 
      match_end: match_end, 
      replacement: replacement, 
      message: message, 
      level:"WARNING",
      code: code,
      full_line: full_line,
    )
  end

  def self.error(path: "", idx: 0, match_start: 0, match_end: 1, replacement: nil, message: "No message", code: "GTN000", full_line: "")
    self.message(
      path: path,
      idx: idx,
      match_start: match_start, 
      match_end: match_end, 
      replacement: replacement, 
      message: message, 
      level:"ERROR",
      code: code,
      full_line: full_line,
    )
  end

  def self.message(path: "", idx: 0, match_start: 0, match_end: 1, replacement: nil, message: "No message", level: "WARNING", code: "GTN000", full_line: "")
    end_area = { "line" => idx + 1, "column" => match_end}
    if match_end == full_line.length 
      end_area = { "line" => idx + 2, "column" => 1}
    end

    res = {
      "message" => message,
      'location' => {
        'path' => path,
        'range' => {
          'start' => { "line" => idx + 1, "column" => match_start + 1},
          'end' => end_area
        }
      },
      "severity" => level
    }
    if !code.nil? 
      res["code"] = {
        "value" => code,
        "url" => @CODE_URL + "#" + code,
      }
    end
    if !replacement.nil?
      res['suggestions'] = [{
        'text' => replacement,
        'range' => {
          'start' => { "line" => idx + 1, "column" => match_start + 1 },
          'end' => end_area
        }
      }]
    end
    res
  end
end

module GtnLinter
  @BAD_TOOL_LINK = /{% tool (\[[^\]]*\])\(https?.*tool_id=([^)]*)\)\s*%}/i

  def self.find_matching_texts(contents, query)
    contents.map.with_index { |text, idx|
      [idx, text, text.match(query)]
    }.select { |idx, text, selected| selected }
  end

  def self.fix_notoc(contents)
    self.find_matching_texts(contents, /{:\s*.no_toc\s*}/)
        .map { |idx, text, selected|
      ReviewDogEmitter.delete_text(
        path: @path,
        idx: idx, 
        text: text,
        message: "Setting {: .no_toc} is discouraged, these headings provide useful places for readers to jump to.",
        code: "GTN:001",
        full_line: text,
      )
    }
  end

  # GTN:002 youtube discouraged
  def self.youtube_bad(contents)
    self.find_matching_texts(contents, /<iframe.*youtu.?be.*<\/iframe>/)
        .map { |idx, text, selected|
      ReviewDogEmitter.delete_text(
        path: @path,
        idx: idx, 
        text: text,
        message: "Instead of embedding IFrames to YouTube contents, consider adding this video to the GTN Video Library where it will be more visible for others. https://github.com/gallantries/video-library/issues/",
        code: "GTN:002"
      )
    }
  end

  def self.link_gtn_tutorial_external(contents)
    self.find_matching_texts(
      contents,
      /\((https?:\/\/(training.galaxyproject.org|galaxyproject.github.io)\/training-material\/(.*tutorial).html)\)/
    )
    .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        # We wrap the entire URL (inside the explicit () in a matching group to make it easy to select/replace)
        match_start: selected.begin(1),
        match_end: selected.end(1) + 1,
        replacement: "{% link #{selected[3]}.md %}",
        message: "Please use the link function to link to other pages within the GTN. It helps us ensure that all links are correct",
        code: "GTN:003",
      )
    }
  end

  def self.link_gtn_slides_external(contents)
    self.find_matching_texts(
      contents,
      /\((https?:\/\/(training.galaxyproject.org|galaxyproject.github.io)\/training-material\/(.*slides.html))\)/
    )
    .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(1),
        match_end: selected.end(1) + 1,
        replacement:"{% link #{selected[3]} %}",
        message: "Please use the link function to link to other pages within the GTN. It helps us ensure that all links are correct",
        code: "GTN:003",
      )
    }
  end

  def self.check_dois(contents)
    self.find_matching_texts(contents, /(\[[^]]*\]\(https?:\/\/doi.org\/[^)]*\))/)
      .select{|idx, text, selected| ! selected[0].match(/10.5281\/zenodo/) } # Ignoring zenodo
        .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(0),
        match_end: selected.end(0) + 2,
        replacement: "{% cite ... %}",
        message: "This looks like a DOI which could be better served by using the built-in Citations mechanism. You can use https://doi2bib.org to convert your DOI into a .bib formatted entry, and add to your tutorial.md",
        code: "GTN:004"
      )
    }
  end

  def self.check_bad_link_text(contents)
    self.find_matching_texts(contents, /\[\s*(here|link)\s*\]/i)
        .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(0),
        match_end: selected.end(0) + 1,
        replacement: "[Something better here]",
        message: "Do not use 'here' as your link title, it is " +
         "[bad for accessibility](https://usability.yale.edu/web-accessibility/articles/links#link-text). " +
         "Instead try restructuring your sentence to have useful descriptive text in the link.",
        code: "GTN:005",
      )
    }
  end

  def self.incorrect_calls(contents)
    a = self.find_matching_texts(contents, /([^{]|^)(%\s*[^%]*%})/i)
            .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(2),
        match_end: selected.end(2) + 1,
        replacement: "{#{selected[2]}",
        message: "It looks like you might be missing the opening { of a jekyll function",
        code: "GTN:006",
      )
    }
    b = self.find_matching_texts(contents, /{([^%]\s*[^%]* %})/i)
            .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(1),
        match_end: selected.end(1) + 1,
        replacement: "%#{selected[1]}",
        message: "It looks like you might be missing the opening % of a jekyll function",
        code: "GTN:006",
      )
    }

    c = self.find_matching_texts(contents, /({%\s*[^%]*%)([^}]|$)/i)
            .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(1),
        match_end: selected.end(1) + 2,
        replacement: "#{selected[1]}}#{selected[2]}",
        message: "It looks like you might be missing the closing } of a jekyll function",
        code: "GTN:006",
      )
    }

    d = self.find_matching_texts(contents, /({%\s*[^}]*[^%])}/i)
            .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(1),
        match_end: selected.end(1) + 1,
        replacement: "#{selected[1]}%",
        message: "It looks like you might be missing the closing % of a jekyll function",
        code: "GTN:006",
      )
    }
    a + b + c + d
  end

  def self.non_existent_snippet(contents)
    self.find_matching_texts(contents, /{%\s*snippet\s+([^ ]*)/i)
        .select { |idx, text, selected|
      !File.exists?(selected[1])
    }
        .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(0),
        match_end: selected.end(0),
        replacement: nil,
        message: "This snippet (`#{selected[1]}`) does not seem to exist",
        code: "GTN:008",
      )
    }
  end

  def self.bad_tool_links(contents)
    self.find_matching_texts(contents, @BAD_TOOL_LINK)
        .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(0),
        match_end: selected.end(0) + 1,
        replacement: "{% tool #{selected[1]}(#{selected[2]}) %}",
        message: "You have used the full tool URL to a specific server, here we only need the tool ID portion.",
        code: "GTN:009",
      )
    }
  end

  def self.new_more_accessible_boxes(contents)
    #  \#\#\#
    self.find_matching_texts(contents, /> (### {% icon ([^%]*)%}[^:]*:(.*))/)
        .map { |idx, text, selected|
      key = selected[2].strip.gsub(/_/, '-')
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(1),
        match_end: selected.end(1) + 1,
        replacement: "> <#{key}-title>#{selected[3].strip}</#{key}-title>",
        message: "We have developed a new syntax for box titles, please consider using this instead.",
        code: "GTN:010",
      )
    }
  end

  def self.no_target_blank(contents)
    self.find_matching_texts(contents, /target=("_blank"|'_blank')/)
        .map { |idx, text, selected|
      ReviewDogEmitter.warning(
        path: @path,
        idx: idx, 
        match_start: selected.begin(0),
        match_end: selected.end(0),
        replacement: nil,
        message: "Please do not use `target=\"_blank\"`, [it is bad for accessibility.](https://www.a11yproject.com/checklist/#identify-links-that-open-in-a-new-tab-or-window)",
        code: "GTN:011",
      )
    }
  end

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
      *new_more_accessible_boxes(contents),
      *no_target_blank(contents),
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
        if !x.title
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
    bad_keys.each { |key, reason|
      results += self.find_matching_texts(contents, /^\s*@.*{#{key},/)
                     .map { |idx, text, selected|
        ReviewDogEmitter.warning(
          path: @path,
          idx: idx, 
          match_start: 0,
          match_end: text.length,
          replacement:  nil,
          message: reason,
          code: "GTN:012",
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
      results.each { |r| puts JSON.generate(r) }
    elsif path.match(/.bib$/)
      handle = File.open(path)
      contents = handle.read.split("\n")

      bib = BibTeX.open(path)
      results = fix_bib(contents, bib)
      results.each { |r| puts JSON.generate(r) }
    end
  end
end

if $0 == __FILE__
  linter = GtnLinter
  linter.fix_file(ARGV[0])
end
