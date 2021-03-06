require 'date'
require 'pdf/reader'
require 'paperless/date_search'
include DateSearch

module Paperless

  PDF_EXT   = 'pdf'
  DATE_VAR  = '<date>'
  MATCH_VAR = '<match>'
  FILEDATE  = 'filedate'
  TODAY     = 'today'

	class Engine

    PDFPEN_ENGINE         = 'pdfpen'
    PDFPENPRO_ENGINE      = 'pdfpenpro'
    ACROBAT_ENGINE        = 'acrobat'
    DEVONTHINKPRO_ENGINE  = 'devonthinkpro'
    DEVONTHINKPRO_SERVICE = 'devonthinkpro'
    FINDER_SERVICE        = 'finder'
    EVERNOTE_SERVICE      = 'evernote'

    attr_reader :service

		def initialize(options)
      @destination         = nil
      @service             = nil
      @title               = nil
      @date                = DateTime.now
      @tags                = Array.new()
      
      @file                = options[:file]
      @text_ext            = options[:text_ext]
      @pdf_ext             = [Paperless::PDF_EXT]
      @default_service     = options[:default_service]
      @date_format         = options[:date_format]
      @date_locale         = options[:date_locale]
      @date_default        = options[:date_default]
      @default_destination = options[:default_destination]
      @rules               = Array.new()

			options[:rules].each do |rule|
				@rules.push Paperless::Rule.new(rule)
			end

      @ocr_engine = options[:ocr_engine]||false
		end

		def process_rules
      markdown_ext = ['md','mmd']
			text_ext = @text_ext + markdown_ext
			file_ext = File.extname(@file).gsub(/\./,'')

			if file_ext == Paperless::PDF_EXT
        
        self.process_pdf

      elsif text_ext.index file_ext

        self.process_text
      
      else
      	puts "Unknown file type. No rules were processed."
      end
		end

		def add_tags(tags)
			if tags.length > 0
				@tags = (@tags + tags).collect {|x| x = x.downcase }
				@tags.uniq!
			end
		end

		def set_destination(destination)
			@destination = destination if destination && @destination.nil?
		end

		def set_title(title)
			@title = title if title && @title.nil?
		end

		def set_service(service)
			@service = service if service && @service.nil?
		end

    def set_date_default()
      puts "Using default date..."
      # Set the default date to the date of the file or else to now
      if @date_default == Paperless::FILEDATE
        t = File.stat(@file).mtime
        @date = Date.new(t.year,t.month,t.day) 
      else
        @date = DateTime.now
      end
    end

    def process_rules_engine(text)
      self.set_date_default if @date.nil?
      # Process each page and pass it through the rules engine
      @rules.each do |rule|
        rule.set_date(@date,@date_format)
        if !rule.matched && rule.match(@file, text)
          self.add_tags(rule.tags)
          self.set_destination(rule.destination)
          self.set_title(rule.title)
          self.set_service(rule.service)
        end
      end
    end

    def process_text
      puts "Processing Text file..."

      text = File.open(@file, "rb") {|io| io.read}

      # Verify that we need to search for date or just set to today
      # Need to prcess file for date in case the rules need to use it.
      # First check if there are actually any date rules
      @rules.each do |rule|
        if rule.condition == Paperless::DATE_VAR
          @date = date_search(text,@date_locale)
        end
      end

      # Process each page and pass it through the rules engine
      process_rules_engine(text)
    end


		def process_pdf
			puts "Processing PDF pages..."

		  reader = PDF::Reader.new(@file)

		  # Verify that we need to search for date or just set to today
		  # Need to prcess file for date in case the rules need to use it.
		  # First check if there are actually any date rules
      @rules.each do |rule|
			  if rule.condition == Paperless::DATE_VAR
			    reader.pages.each do |page|
			    	break if @date = date_search(page.text,@date_locale)
			    end
			    break
	    	end
			end

			# Process each page and pass it through the rules engine
	    reader.pages.each do |page|
        process_rules_engine(page.text)
	    end
		end

		def ocr
			puts "Running OCR on file with #{@ocr_engine}"
      ocr_engine = case @ocr_engine
        when /^#{PDFPENPRO_ENGINE}$/i     then PaperlessOCR::PDFpenPro.new
        when /^#{PDFPEN_ENGINE}$/i        then PaperlessOCR::PDFpen.new
        when /^#{ACROBAT_ENGINE}$/i       then PaperlessOCR::Acrobat.new
        when /^#{DEVONTHINKPRO_ENGINE}$/i then PaperlessOCR::DevonThinkPro.new
        else false
      end
      
      if ocr_engine
        ocr_engine.ocr({:file => @file})
      else
        puts "WARNING: No valid OCR engine was defined."
      end
		end

		def create(options)
      # May need to externalize this so other methods can access it.
      service = case @service.nil? ? @default_service : @service
        when /^#{EVERNOTE_SERVICE}$/i then PaperlessService::Evernote.new
        when /^#{FINDER_SERVICE}$/i then PaperlessService::Finder.new
        when /^#{DEVONTHINKPRO_SERVICE}$/i then PaperlessService::DevonThinkPro.new
        else false
      end

      if service
        self.print
        
        destination = @destination.nil? ? @default_destination : @destination
        # :created => @date
        service.create({ 
          :delete => options[:delete], 
          :destination => destination, 
          :text_ext => @text_ext, 
          :file => @file, 
          :date => @date, 
          :title => @title, 
          :tags => @tags
        })
      else 
        puts "WARNING: No valid Service was defined."
      end
		end

		def print
      service = @service.nil? ? @default_service : @service
      title = @title.nil? ? File.basename(@file) : @title

      destination = @destination.nil? ? @default_destination : @destination
      if destination == PaperlessService::Finder::NO_MOVE && service == PaperlessService::FINDER.downcase
        destination = File.dirname(@file)
      end

      puts "* ---------------------------------------------"
			puts "* File: #{@file}"
      puts "* Service: #{service}"
			puts "* Destination: #{destination}"
			puts "* Title: #{title}"
			puts "* Date: #{@date.strftime('%Y-%m-%d')}"
			puts "* Tags: #{@tags.join(', ')}"
      puts "* ---------------------------------------------"
		end

	end

end
