require 'active_support'
require 'active_support/core_ext'

require 'memoist'

require 'lingua/stemmer'
require 'unicode'


class MatchData

  def to_h
    Hash[names.map(&:to_sym).zip(captures)]
  end

end


class Author

  extend Memoist

  def self.from_match(match)
    surname = match[:surname]
    name = match[:name]
    patronymic = match[:patronymic]
    if name.nil?
      name = patronymic
      patronymic = nil
    end
    if name.blank?
      nil
    else
      new(surname, name, patronymic)
    end
  end

  attr_reader :surname, :name, :patronymic
  def initialize(surname, name, patronymic)
    @surname = surname
    @name = name
    @patronymic = patronymic
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


class Title

  extend Memoist

  def warnings
    @warnings = []
    validate
    @warnings
  end
  memoize :warnings

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
    :title        , 'Заголовок'            ,
    :duration     , 'Длительность'         ,
    :company_name , 'Имя компании'         ,
    :author1      , 'Автор 1'              ,
    :author2      , 'Автор 2'              ,
    :author3      , 'Автор 3'              ,
    :author4      , 'Автор 4'              ,
    :author5      , 'Автор 5'              ,
    :citizenship  , 'Подданство'           ,
    :category     , 'Отрасль производства' ,
    :cert_num     , '№ свидетельства'      ,
    :date_range   , 'Крайние даты'         ,
    :end_year     , 'Дата окончания'       ,
    :code         , 'Архивный шифр'        ,
  ]


  FIELDS.keys.map do |field|
    attr_reader field
  end


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
  memoize :categories

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
      .*?
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
    (company_name.blank? ? '' : 'C') + authors.size.to_s
  end


  (1..5).each do |i|
    define_method("author#{i}") do
      authors[i - 1].try(:full_name)
    end
  end

  def authors
    subject_with_authors[:authors] || []
  end

  PARSED_AUTHOR_REGEX = /
    (?<name>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<patronymic>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<surname>
     (де[\p{Pd}\s]+(л[ая][\p{Pd}\s])?)?
     (фон[\p{Pd}\s]+(дер[\p{Pd}\s])?)?
      \p{Lu}[\p{alpha}\p{Pd}]+
    )
    \s*
    (?<name>\p{Lu}[\p{Ll}.]+)?
    \s*
    (?<patronymic>\p{Lu}[\p{Ll}.]+)?
  /x
  def subject_with_authors
    return {} if subject_with_props[:subject].blank?
    subject = subject_with_props[:subject].clone

    authors = subject.to_enum(:scan, PARSED_AUTHOR_REGEX).map do
      Author.from_match(Regexp.last_match)
    end.compact.to_a

    authors.each do |author|
      subject.gsub!(author.surname, '')
      subject.gsub!(author.name || '', '')
      subject.gsub!(author.patronymic || '', '')
    end

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
    subject_with_props[:citizenship]
  end

  def occupation
    subject_with_props[:occupation]
  end

  def position
    subject_with_props[:position]
  end

  def location
    subject_with_props[:location]
  end


  # прусск: 40
  # германск: 29
  # великобританск: 24
  # французск: 21
  # австрийск: 20
  # итальянск: 20
  # русск: 18
  # шведск: 15
  # американск: 13
  # саксонск: 7
  # швейцарск: 5
  # австро-венгерск: 4
  # бельгийск: 4
  # рижск: 3
  # митавск: 2
  # датск: 2
  # немецк: 2

  countries = [
    'Великобританский подданный',
    'Французский подданный',
    'Германский подданный',
    'Австро-венгерский подданный',
    'Швейцарский подданный',
    'Итальянский подданный',
    'Испанский подданный',
    'Подданный США',
    'Прусский подданный',
    'Австрийский подданный',
    'Русский подданный',
    'Шведский подданный',
    'Саксонский подданный',
    'Бельгийский подданный',
  ].map do |citizenship|
    key = citizenship.sub(/\s*подданный\s*/i, '')
    key = Lingua.stemmer(key, :language => :ru)
    key = Unicode::downcase(key)
    regexp = Regexp.new("(?<!\\p{Alpha})#{key}\\p{Alpha}+", Regexp::IGNORECASE)
    [regexp, citizenship]
  end

  COUNTRIES = Hash[countries]

  CITIZENSHIP_REGEXP = /(?<!\p{Alpha})(поддан\p{Alpha}+|граждан\p{Alpha}+)/i
  FOREIGNER_REGEXP = /(?<!\p{Alpha})(иностран\p{Alpha}+)/i


  stem_and_join = lambda do |pos|
    source = pos.split(' ').map do |w|
      Unicode::downcase(Lingua.stemmer(w, :language => :ru)) + '\\p{alpha}*'
    end.join(' ')
    Regexp.new(source, Regexp::IGNORECASE)
  end

  occupations = %w{
    Инженер
    Механик
    Технолог
    Доктор
    Химик
    Мастер
    Электротехник
    Техник
    Архитектор
    Врач
    Кандидат
  }.map do |occupation|
    key = Lingua.stemmer(occupation, :language => :ru)
    key = Unicode::downcase(key)
    regexp = Regexp.new("(?<!\\p{Alpha})#{key}\\p{Alpha}*", Regexp::IGNORECASE)
    [occupation, regexp]
  end

  multiwords = [
    'Ветеринарный врач',
    'Зубной врач',

    'Горный инженер',
    'Инженер путей сообщения',

    'Оружейный мастер',
    'Булочный мастер',
    'Водопроводный мастер',
    'Жестяных дел мастер',
    'Коробочных дел мастер',
    'Кузнечный мастер',
    'Мастер жестяных дел',
    'Мастер механического цеха',
    'Мельничный мастер',
    'Механических дел мастер',
    'Мыловаренный мастер',
    'Ремесленный мастер',
    'Ткацкий мастер',
    'Фортепианный мастер',
    'Цеховой мастер',
    'Часовых дел мастер',
    'Экипажных дел мастер',

    'Доктор медицины',
    'Кандидат естественных наук',
    'Кандидат законоведения',
    'Кандидат коммерческих наук',
    'Кандидат математических наук',
    'Кандидат прав',
    'Кандидат университета',
    'Кандидат физико-математических наук',
    'Кандидат философии',
    'Кандидат химии',
    'Кандидат юридических наук',

  ].map do |o|
    [o, stem_and_join.call(o)]
  end


  combinations = occupations.permutation(2).map do |o1, o2|
    occupation = o1.first + '-' + Unicode::downcase(o2.first)
    regexp = Regexp.new(o1.second.source + '[\\p{Pd}\\s]*' + o2.second.source,
                        Regexp::IGNORECASE)
    [occupation, regexp]
  end

  OCCUPATIONS = Hash[
    multiwords + combinations + occupations
  ]

  merchant = [
    /купц\p{alpha}+ \d[\p{Pd}oй ]* гильдии/i,
    /(времен\p{alpha}+\s+)?((\d[\p{Pd}oй ]*|первой|второй) гильдии )?купц\p{alpha}+/i,
  ]

  qualifier = /((отставн|действительн)\p{alpha}+ )?/.source
  POSITIONS = merchant + [
    'Князь',
    'Граф',
    'Барон',
    'Дворянин',
    'Мещанин',
    'Крестьянин',

    'Потомственный почетный гражданин',
    'Почетный гражданин',
  ].map(&stem_and_join) + [
    'Титулованый советник',
    'Статский советник',
    'Коллежский советник',
    'Военный советник',
    'Надворный советник',
    'Коллежский асессор',
    'Титулярный советник',
    'Коллежский секретарь',
    'Губернский секретарь',
    'Кабинетский регистратор',
    'Провинциальный секретарь',
    'Синодский регистратор',
    'Коллежский регистратор',
  ].map do |p|
    Regexp.new(qualifier + stem_and_join.call(p).source, Regexp::IGNORECASE)
  end + [
    'Подполковник',
    'Полковник',
    'Штабс-ротмистр',
    'Штабс-капитан',
    'Унтер-офицер',
    'Майор',
    'Капитан',
    'Лейтенант',
    'Подпоручик',
    'Поручик',
  ].map do |p|
    Regexp.new(
      qualifier +
        '((гвардии|артиллерии) )?(инженер[\\p{Pd}\\sу]*)?' +
        stem_and_join.call(p).source,
      Regexp::IGNORECASE)
  end

  LOCATIONS = [
    /жител\p{alpha}+ (города|гор.|г.|д.) \p{lu}\p{ll}+/i,
    /\p{lu}\p{ll}+ губернии/i,
    /(санкт[ \p{Pd}]*)?петербургск\p{alpha}+/i,
    /московск\p{alpha}+/i,
  ]


  def subject_with_props
    return {} if parsed_title[:subject].blank?
    subject = parsed_title[:subject].clone


    occupation = Set.new
    position = Set.new
    citizenship = Set.new
    location = Set.new

    LOCATIONS.each do |regexp|
      subject.gsub!(regexp) do |m|
        location.add m
        ''
      end
    end

    POSITIONS.each do |regexp|
      subject.gsub!(regexp) do |m|
        position.add m
        ''
      end
    end

    OCCUPATIONS.each do |value, regexp|
      subject.gsub!(regexp) do |o|
        occupation.add value
        ''
      end
    end


    subject.gsub!(CITIZENSHIP_REGEXP) do |m|
      citizenship.add :unknown
      ''
    end

    COUNTRIES.each do |regexp, value|
      subject.gsub!(regexp) do |m|
        citizenship.delete :unknown
        citizenship.add value
        ''
      end
    end

    subject.gsub!(FOREIGNER_REGEXP) do |m|
      citizenship.add 'Иностранец'
      ''
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
  memoize :subject_with_props

  def stripped_subject
    subject_with_authors[:subject]
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
      (привилегии\s)?
      (?<duration>на\s\d+\s?(год|года|лет)\s)?
      (привилегии\s)?
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

  def parsed_title
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
    validate_required_fields_present
    validate_line_count
    validate_parsed_title
    validate_authors
    validate_citizenship
  end


  def validate_authors
    # warn "No authors parsed" if authors.empty? && company_name.blank?
    warn "Suspicious author count" if authors.count > 3
  end


  def validate_citizenship
    warn "Unknown citizenship" if citizenship.blank?
  end


  def validate_line_count
    warn "Suspicious line count" unless lines.count.in? 2..4
  end

  def validate_parsed_title
    warn "Can't parse title" if title.present? &&title.present? && parsed_title.size == 0
  end


  REQUIRED_FIELDS =
    [:title, :code].to_set
  # REQUIRED_FIELDS =
  #   [:author_name, :author_surname, :title, :end_year, :code].to_set

  def validate_required_fields_present
    REQUIRED_FIELDS.each do |field|
      if send(field).nil?
        warn "Missing #{field}"
      end
    end
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


  SPEC_FIELDS = %i{
    code
    title
    cert_num
    date_range
    end_year
    object
    subject
    stripped_subject
    duration
    company_name
    authors
    citizenship
    occupation
    position
    location
  }

  def to_spec
    {
      :input => full_str,
      :output => Hash[SPEC_FIELDS.map{ |field| [field, send(field)] } ]
      # :output => Hash[FIELDS.keys.map{ |field| [field, send(field)] } ]
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
    Category.new(line).tap do |category|
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
    p correct
    p control.size
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

  def stats
    {
      "Total records" => titles.size,
      "Invalid records" => invalid_titles.size
    }
  end
end
