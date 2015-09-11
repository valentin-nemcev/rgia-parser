require 'active_support'
require 'active_support/core_ext'

require 'memoist'

require 'strscan'

require 'lingua/stemmer'
require 'unicode'

require_relative 'regexps'
require_relative 'token_parser'


class MatchData

  def to_h
    Hash[names.map(&:to_sym).zip(captures) + [[:full, to_s]]]
  end

end


class Author

  extend Memoist

  def self.others(match, transfer_target)
    @others ||= new('другие', nil, nil, transfer_target)
  end

  def self.from_match(match, transfer_target)
    surname = match[:surname]
    name = match[:nameB] || match[:nameA]
    patronymic = match[:patronymicB] || match[:patronymicA]
    if name.nil?
      name = patronymic
      patronymic = nil
    end
    if name.blank?
      nil
    else
      new(surname, name, patronymic, transfer_target)
    end
  end

  attr_reader :surname, :name, :patronymic, :transfer_target
  attr_writer :surname

  def initialize(surname, name, patronymic, transfer_target)
    @surname = surname
    @name = name
    @patronymic = patronymic
    @transfer_target = transfer_target
  end


  def initials
    [name, patronymic]
      .compact.map { |name| name[0, 1].upcase + '.' }
      .join(' ').tap { |initials| return initials.blank? ? nil : initials }
  end
  memoize :initials

  def full_name
    [surname, name, patronymic].compact.join(' ')
  end

end


class Token

  attr_reader :type, :matched, :value

  def initialize(type, matched, value = nil)
    @type = type
    @matched = matched
    @value = value
  end

  def to_yaml
    [type, matched, value].compact
  end

end


class Title

  extend Memoist

  def warnings
    @warnings = []
    validate
    @warnings
  end
  memoize :warnings

  def warnings_s
    warnings.join(', ')
  end

  def warn(msg)
    @warnings << msg
    self
  end

  # FIELDS = ActiveSupport::OrderedHash[
  #   :author_name        , 'Имя автора изобретения',
  #   :author_patronymic  , 'Отчество автора изобретения',
  #   :author             , 'Фамилия автора изобретения',
  #   :author_initials    , 'Инициалы автора изобретения',
  #   :trustee_name       , 'Имя доверенного лица',
  #   :trustee_patronymic , 'Отчество доверенного лица',
  #   :trustee_surname    , 'Фамилия доверенного лица',
  #   :trustee_initials   , 'Инициалы доверенного лица',
  #   :title              , 'Заголовок',
  #   :cert_num           , '№ свидетельства',
  #   :date_range         , 'Крайние даты',
  #   :end_year           , 'Дата окончания',
  #   :code               , 'Архивный шифр',
  #   :notes              , 'Замечания',
  #   :tags_str           , 'Классификаторы',
  # ]


  FIELDS = ActiveSupport::OrderedHash[
    :duration     , 'Длительность'         ,
    :author_stat  , 'Кол-во авторов'       ,
    :company_name , 'Имя компании'         ,
    :author1      , 'Автор 1'              ,
    :author2      , 'Автор 2'              ,
    :author3      , 'Автор 3'              ,
    :author4      , 'Автор 4'              ,
    :author5      , 'Автор 5'              ,
    :citizenship_s, 'Подданство'           ,
    :occupation_s , 'Профессия'            ,
    :position_s   , 'Сословие/чин'         ,
    :location_s   , 'Местоположение'       ,
    :category_s   , 'Отрасль производства' ,
    :cert_num     , '№ свидетельства'      ,
    :date_range   , 'Крайние даты'         ,
    :end_year     , 'Дата окончания'       ,
    :code         , 'Архивный шифр'        ,
    :stripped_subject_with_authors, 'Очищенный заголовок',
    :title        , 'Заголовок'            ,
    # :warnings_s   , 'Проблемы'             ,
  ]


  attr_reader :lines

  def initialize
    @lines = []
  end

  def parse_line(line)
    @lines << line
  end


  def category=(cat)
    @category = cat
  end

  def category_s
    category.to_s
  end

  def category
    @category || classifier_category
  end

  def classifier_category
    categories.first
  end

  def classified_correctly?
    @category == classifier_category
  end

  def categories
    category_scores.map(&:second)
  end

  def category_scores
    @category_scores || []
  end

  def category_scores=(scores)
    @category_scores = scores.take(3).map do |category, score|
      [Math.log(score), category]
    end
  end


  def category_best_score
    category_scores.first[0]
  end


  def confidence_score
    scores = category_scores.take(2).map(&:first)
    scores.first - scores.last
  end
  memoize :confidence_score


  def needs_classification?
    @category.nil? && object.present?
  end


  CODE_REGEX = /^(ргиа\.?\s*)?ф\.?\s*\d+ .*? $/xi
  def code
    CODE_REGEX.match(full_str) do |m|
      return m[0].sub(/[\s.]*$/, '')
    end
  end
  memoize :code


  def date_range
    dates[:range]
  end


  def end_year
    dates[:end_year]
  end


  DATES_REGEX = /
    ^\s*
    (?<range>
      (\d+ \s* \p{Alpha}+ \s* \d+)?
      [\p{P}\s]*?
      (\d+ \s* \p{Alpha}+ \s*)? (?<end_year>\d{4})
    )
    [\s.]*
    $
  /xui
  def dates
    DATES_REGEX.match(full_str).to_h
  end
  memoize :dates


  def cert_num
    cert_num_parens
  end


  CERT_NUM_PARENS_REGEX = /
    \(\s* (?:привилегия|патент) .*? (\d+) \)[\s.]*
  /xi

  def cert_num_parens
    CERT_NUM_PARENS_REGEX.match(full_str) do |m|
      return m[1]
    end
  end
  memoize :cert_num_parens


  def author_stat
    (company_name.blank? ? '' : 'Компания, ') + authors.size.to_s
  end


  (1..5).each do |i|
    define_method("author#{i}") do
      authors[i - 1].try(:full_name)
    end
  end

  def authors
    parsed_subject_tokens[:authors].to_a
  end

  PARSED_AUTHOR_REGEX = /
    (?<nameB>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<patronymicB>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<surname>
     (де[\p{Pd}\s]+(л[ая][\p{Pd}\s])?)?
     (фон[\p{Pd}\s]+(дер[\p{Pd}\s])?)?
      \p{Lu}[\p{alpha}\p{Pd}]+
    )
    \s*
    (?<nameA>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<patronymicA>\p{Lu}[\p{Ll}.]+)?
  /x

  OTHERS_REGEX = /(?<others>друг\p{alpha}+)/i
  TRANSFER_REGEX = /(?<transfer>переда\p{alpha}+)/i
  AUTHOR_REGEX = Regexp.union [PARSED_AUTHOR_REGEX, OTHERS_REGEX, TRANSFER_REGEX]


  def subject_with_authors
    return {} if subject_with_props[:subject].blank?
    subject = subject_with_props[:subject].clone

    transfer = nil
    authors = subject.to_enum(:scan, AUTHOR_REGEX).map do
      m = Regexp.last_match.to_h
      if m[:transfer]
        transfer = true
        next
      elsif m[:others]
        Author.others(m, transfer)
      else
        Author.from_match(m, transfer)
      end
    end.compact.to_a

    authors.each do |author|
      subject.gsub!(author.surname, '')
      subject.gsub!(author.name || '', '')
      subject.gsub!(author.patronymic || '', '')
    end

    subject.gsub!(TRANSFER_REGEX, '')
    subject.gsub!(OTHERS_REGEX, '')
    subject.gsub!(',', '')
    subject.gsub!(/(^|\s)и/, '')
    subject.gsub!(/\s+/, ' ')
    subject.strip!
    {subject: subject, authors: authors}
  end
  memoize :subject_with_authors


  COMPANY_REGEXES = %w{
    обществ
    акционерн
    фирм
    завод
    компан
    товариществ
    торгов
    дом
    фабрик
  }.map do |company|
    Regexp.new("(?<!\\p{Alpha})#{company}", Regexp::IGNORECASE)
  end

  def company_name
    COMPANY_REGEXES.each do |regex|
      return subject if regex.match(subject)
    end
    nil
  end
  memoize :company_name


  def citizenship
    citizenship = parsed_subject_tokens[:citizenship].to_a
    if citizenship.empty?
      ['Российский подданный']
    else
      citizenship
    end
  end

  def citizenship_s
    citizenship.join(', ')
  end

  def occupation
    parsed_subject_tokens[:occupation].to_a
  end

  def occupation_s
    occupation.join(', ')
  end

  def position
    parsed_subject_tokens[:position].to_a
  end

  def position_s
    position.join(', ')
  end

  def location
    parsed_subject_tokens[:location].to_a
  end

  def location_s
    location.join(', ')
  end




  def subject_with_props_old
    return {} if parsed_title[:subject].blank?
    subject = parsed_title[:subject].clone


    occupation = Set.new
    position = Set.new
    citizenship = Set.new
    location = Set.new

    LOCATIONS.each do |regexp, valueProc|
      subject.gsub!(regexp) do
        m = Regexp.last_match
        location.add valueProc.call(m)
        ''
      end
    end

    POSITIONS.each do |regexp, valueProc|
      subject.gsub!(regexp) do
        m = Regexp.last_match
        position.add valueProc.call(m)
        ''
      end
    end

    OCCUPATIONS.each do |regexp, valueProc|
      subject.gsub!(regexp) do
        m = Regexp.last_match
        occupation.add valueProc.call(m)
        ''
      end
    end


    CITIZENSHIPS.each do |regexp, valueProc|
      subject.gsub!(regexp) do
        m = Regexp.last_match
        citizenship.add valueProc.call(m)
        ''
      end
    end

    if citizenship.empty?
      citizenship.add 'Российский подданный'
    end

    subject.strip!
    subject.gsub!(/\s+/, ' ')
    {
      subject: subject,
      occupation: occupation.to_a,
      position: position.to_a,
      location: location.to_a,
      citizenship: citizenship.to_a
    }
  end
  memoize :subject_with_props_old


  TOKENS = ActiveSupport::OrderedHash[
    :occupation  , OCCUPATIONS ,
    :position    , POSITIONS   ,
    :citizenship , CITIZENSHIPS,
    :location    , LOCATIONS   ,
    :company_type, COMPANY_TYPES,
    :duration, [
      [/с продлением срока действия до ((\d+) (год|года|лет))\s*/,
      proc {|m| m[1]}]
    ],
    :open_quote, [
      [/\p{Pi}\s*/, :matched.to_proc]
    ],
    :close_quote, [
      [/\p{Pf}\s*/, :matched.to_proc]
    ],
    :initial, [
      [/\p{Lu}\.\s*/, :matched.to_proc]
    ],
    :surname, [
      [/(?<surname>
      (де[\p{Pd}\s]+(л[ая][\p{Pd}\s])?)?
      (фон[\p{Pd}\s]+(дер[\p{Pd}\s])?)?
        \p{Lu}[\p{alpha}\p{Pd}]+
      )\s*/x, proc { |m| m.matched } ],
      [/(друг\p{alpha}+)\s*/i, proc { 'другие' }]
    ],
    :connector, CONNECTORS,
  ]

  def subject_tokens
    tokens = []
    scanner = StringScanner.new(parsed_title[:subject].to_s)

    loop do
      consumed = catch :next do
        TOKENS.each do |token, regexps|
          regexps.each do |regexp, valueProc|
            if scanner.scan(regexp)
              tokens << Token.new(token, scanner.matched, valueProc.call(scanner))
              throw :next, true
            end
          end
        end
        if scanner.scan(/\p{word}+\s*/)
          tokens << Token.new(:word, scanner.matched)
          throw :next, true
        end
        if scanner.scan(/\p{punct}+\s*/)
          tokens << Token.new(:punct, scanner.matched)
          throw :next, true
        end
      end
      break unless consumed
    end
    if scanner.rest?
      tokens << Token.new(:rest, scanner.rest)
    end
    tokens
  end
  memoize :subject_tokens


  def parsed_subject_tokens
    parser = TokenParser.new(subject_tokens)
    parser.parse
  end
  memoize :parsed_subject_tokens


  def stripped_subject
    subject_with_authors[:subject]
  end


  def stripped_subject_with_authors
    parsed_subject_tokens[:subject]
  end


  def subject
    parsed_title[:subject]
  end


  def object
    parsed_title[:object].try{ |t| t.gsub(/s+/, ' ')}
  end
  memoize :object


  def duration
    parsed_title[:duration].try{ |t| t.strip }
  end
  memoize :duration


  PARSED_TITLE_REGEXES = [
    /
      ^
      дело\sо\sвыдаче\s
      (привилегии[\p{p}\p{z}]+)?
      (?<duration>на\s\d+\s?(год|года|лет)\s)?
      (привилегии[\p{p}\p{z}]+)?
      (?<subject>.*?)
      \s(?:на|для)\s(?!\d+\s?(год|года|лет)\s)
      (?<object>.*?)
      (?<subject_company>
        [,\s]+передан\p{Alpha}+
        .*?
      )?
      $
    /xi,
    /
      ^
      по\sходатайству\s
      (?<subject>.*?)
      \s(?:о)\s
      (?<object>.*?)
      $
    /xi,
  ]

  NOT_PARSED_TITLE_REGEXES = [/[\p{p}\p{z}]то же[\p{p}\p{z}]/i]

  def parsed_title
    NOT_PARSED_TITLE_REGEXES.each do |regex|
      if regex.match(title)
        return {}
      end
    end
    PARSED_TITLE_REGEXES.each do |regex|
      m = regex.match(title)
      next if m.nil?
      return m.to_h.tap do |h|
        h[:subject] += h[:subject_company] if h[:subject_company].present?
      end
    end
    return {}
  end
  memoize :parsed_title


  def title
    lines.first
      .sub(CERT_NUM_PARENS_REGEX, '')
      .sub(/[\s.]*$/, '')
  end
  memoize :title


  def full_str
    @full_str ||= @lines.join("\n").squeeze(' ')
  end
  memoize :full_str


  def validate
    validate_line_count
    validate_parsed_title
    validate_authors
    validate_citizenship
  end


  def validate_authors
    # warn "No authors parsed" if authors.empty? && company_name.blank?
    # warn "Suspicious author count" if authors.count > 3
  end


  def validate_citizenship
    warn "Unknown citizenship" if citizenship.include? :unknown
  end


  def validate_line_count
    warn "Suspicious line count" unless lines.count.in? 2..4
  end

  def validate_parsed_title
    warn "Can't parse title" if title.present? &&title.present? && parsed_title.size == 0
  end


  def valid?
    warnings.empty?
  end


  def to_row
    FIELDS.keys.map do |field|
      send field
    end
  end
  memoize :to_row

  def categories_dbg
    "\n" + category_scores.map do |score, category|
      [score.round(4), category.to_s].join(' ')
    end.join("\n")
  end
  memoize :categories_dbg


  def subject_tokens_yaml
    subject_tokens.map(&:to_yaml)
  end

  def authors_yaml
    authors.map(&:full_name)
  end

  SPEC_FIELDS = %i{
    code
    title
    cert_num
    date_range
    end_year
    object
    subject
    subject_tokens_yaml
    duration
    authors_yaml
    citizenship
    occupation
    position
    location
  }

  def to_spec
    {
      :input => full_str,
      :output => Hash[SPEC_FIELDS.map{ |field| [field, send(field)] } ]
    }
  end
  memoize :to_spec

end



class Titles

  include Enumerable
  extend Forwardable
  def_delegators :@titles, :each, :to_a, :sample, :size
  def_delegators :titles_hash, :[], :values_at
  attr_reader :titles
  attr_reader :classifier_examples, :classifier_categories

  def initialize
    @titles = []
    @current_title = nil
    @classifier_examples = []
    @current_classifier_example = nil
    @classifier_categories = Hash.new
  end

  def titles_hash
    @titles_hash ||= Hash[titles.map{ |t| [t.code, t]}]
  end


  TITLE_END_REGEP = Title::CODE_REGEX

  def next_title
    @current_title = nil
  end

  def current_title
    @current_title ||= Title.new.tap { |t| @titles.push(t) }
  end

  def parse_line(line)
    line.strip!
    return if line.blank?

    current_title.parse_line(line)
    next_title if TITLE_END_REGEP.match(line)
  end


  def next_classifier_example
    @current_classifier_example = nil
  end

  def current_classifier_example
    @current_classifier_example ||=
      ClassifierExample.new(classifier_categories).tap do |t|
        @classifier_examples.push(t)
      end
  end
  CLASSIFIER_EXAMPLE_START_REGEXP = Regexp.new('^\s*ргиа', Regexp::IGNORECASE)

  def parse_classifier_example_line(line)
    line.strip!
    return if line.blank?

    next_classifier_example if CLASSIFIER_EXAMPLE_START_REGEXP.match(line)
    current_classifier_example.parse_line(line)
  end


  def parse_category_line(line)
    Category.parse(line).tap do |category|
      classifier_categories[category.number] = category
    end
  end

  def classified_titles
    @classified_titles ||= classifier_examples.map do |example|
      title = self[example.code]
      if title.nil?
        puts "Unknown example: #{example.code}"
      else
        title.category = example.category
      end
      title
    end.compact
  end

  def classify(classifier)
    classifier.train(classified_titles)
    classified = Parallel.map(titles, :progress => "Classifying") do |title|
      classifier.classify(title) if title.needs_classification?
      title
    end
    titles.replace classified
  end

  def evaluate_classifier(classifier)
    control_ratio = 0.3
    train, control = classified_titles.partition{ rand > control_ratio }
    classifier.train(train)
    control = Parallel.map(control, :progress => "Classifying") do |title|
      classifier.classify(title)
      title
    end
    correct = control.count(&:classified_correctly?)
    correct_p = (correct.to_f/control.size).round(2) * 100
    puts "Correctly classified records #{correct_p}%"
  end

  def invalid_titles
    titles.reject(&:valid?)
  end

  def with_worst_category_scores(n)
    titles
    .select(&:needs_classification?)
    .sort_by(&:confidence_score).first(n)
  end

  def categories_stats
    s = Hash.new(0)
    classifier_categories.values.each { |cat| s[cat] = 0 }
    titles
      .map{ |t| t.category || Category.nil_category }
      .each { |cat| s[cat] += 1 }
    s.to_a
  end

  def stats
    {
      "Total records" => titles.size,
      "Invalid records" => invalid_titles.size
    }
  end
end
