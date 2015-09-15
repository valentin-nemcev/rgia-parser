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

citizenships = [
  'Великобританский подданный',
  'Французский подданный',
  'Германский подданный',
  'Австро-венгерский подданный',
  'Швейцарский подданный',
  'Итальянский подданный',
  'Испанский подданный',
  'Подданный США',
  'Американский подданный',
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
  regexp = /(?<!\p{Alpha})#{key}\p{Alpha}+\s+(поддан\p{Alpha}+|граждан\p{Alpha}+)?\s*/i
  [regexp, proc { citizenship }]
end

citizenships << [/(?<!\p{Alpha})(иностран\p{Alpha}+)\s*/i, proc {'Иностранец'}]

CITIZENSHIPS = Hash[citizenships]


stem_and_join = lambda do |pos|
  source = pos.split(' ').map do |w|
    Unicode::downcase(Lingua.stemmer(w, :language => :ru)) + '\\p{alpha}*'
  end.join(' ')
  Regexp.new(source+'\\s*', Regexp::IGNORECASE)
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
  regexp = /(?<!\p{Alpha})#{key}\p{Alpha}*\s*/i
  [regexp, proc { occupation }]
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
  [stem_and_join.call(o), proc { o }]
end


combinations = occupations.permutation(2).map do |o1, o2|
  occupation = proc {o1.second.call() + '-' + Unicode::downcase(o2.second.call()) }
  regexp = Regexp.new(o1.first.source + '[\\p{Pd}\\s]*' + o2.first.source + '\\s*',
                      Regexp::IGNORECASE)
  [regexp, occupation]
end

OCCUPATIONS = Hash[
  multiwords + combinations + occupations
]

merchant = [
  [
    /купц\p{alpha}+ (\d)[\p{Pd}oй ]* гильдии\s*/i,
    proc { |m| "Купец #{m[1]}-й гильдии" }
  ],
  [
    /(времен\p{alpha}+\s+)?((?<guild>\d[\p{Pd}oй ]*|первой|второй) гильдии )?купц\p{alpha}{,2}\s*/i,
    proc do |m|
      if m[:guild].present?
        guild = case m[:guild][0]
                when 'п' then 1
                when 'в' then 2
                else m[:guild][0]
                end
        guild = " #{guild}-й гильдии"
      else
        guild = ""
      end
      "Купец" + guild
  end
  ]
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
].map{ |s| [stem_and_join.call(s), proc { s }] } + [
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
].map do |s|
  r = Regexp.new(qualifier + stem_and_join.call(s).source + '\\s*', Regexp::IGNORECASE)
  [r, proc { s }]
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
].map do |s|
  r = Regexp.new(
    qualifier +
      /((запаса армии|гвардии|артиллерии) )?(инженер[\p{Pd}\sу]*)?/.source +
      stem_and_join.call(s).source +
      /(запаса армии )?/i.source,
    Regexp::IGNORECASE)
  [r, proc { s }]
end

LOCATIONS = [
  [
    /(жител\p{alpha}+|приписанн\p{alpha}+ к) (города|гор.|г.|д.) (?<name>\p{lu}\p{ll}+)\s*/i,
    proc { |m| 'г. ' + Unicode::capitalize(m[:name]) }
  ],
  [
    /(?<name>\p{lu}\p{ll}+) губернии\s*/i,
    proc { |m| Unicode::capitalize(m[:name]) + ' губернии' }
  ],
  [
    /(санкт[ \p{Pd}]*)?петербургск\p{alpha}+\s*/i,
    proc { 'Санкт-Петербург' }
  ],
  [/московск\p{alpha}+\s*/i, proc { 'Москва' }]
]


COMPANY_TYPES = [
  'Товарищество',
  'Торговый дом',
  'Банкирский дом',
  'Акционерное общество',
  'Международная компания',
  'Международное общество',
  'Общество',
  'Компания',
  'Фирма',
  'Дирекция',
  'Патентное бюро',
  'Синдикат',
  'Завод',
  'Фабрика',
  'Управление',
].map do |o|
  [stem_and_join.call(o), proc { o }]
end

COMPANY_TYPE_QUALIFIERS = [
  [/с ограниченной ответственностью\s*/i, :matched.to_proc],
  [/(,)? бывш[\.\p{alpha}]+\s*/i,:matched.to_proc]
]

PROPER_NAMES = [
  [/
    (де[\p{Pd}\s]+(л[еая][\p{Pd}\s])?)?
    (фон[\p{Pd}\s]+(дер[\p{Pd}\s])?)?
    (д['ˈ])?
    \p{Lu}[\p{alpha}\p{Pd}]+
    (\s+(Дж.|младш\p{alpha}+))?
    \s*/x, proc { |m| m.matched } ],
  [/(друг\p{alpha}+|др.|прочее)\s*/i, proc { 'другие' }],
  [/К°/i, proc { 'К°' }],
]


CONNECTORS = [
  /и\s+/,
  /(,)?\s*c передач\p{alpha}+\s*/i,
  /(,)?\s*передан\p{alpha}+( затем)?( в( совместную)?собственность)?\s*/i,
  /(,)?\s*торгующ\p{alpha}+ под\s*/i,
  /(,)?\s*служащ\p{alpha}+ в\s/i,
  /,\s*/
].map do |r|
  [r, proc { |m| m.matched }]
end


TOKENS = ActiveSupport::OrderedHash[
  :occupation  , OCCUPATIONS ,
  :position    , POSITIONS   ,
  :citizenship , CITIZENSHIPS,
  :location    , LOCATIONS   ,
  :company_type, COMPANY_TYPES,
  :company_type_qualifier, COMPANY_TYPE_QUALIFIERS,
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
    [/\p{L}\p{Ll}?\.\s*/, proc { |m| Unicode::upcase(m.matched).strip + ' ' }]
  ],
  :proper_name, PROPER_NAMES,
  :connector, CONNECTORS,
]

class SubjectTokenizer

  attr_reader :scanner, :tokens

  def initialize(subject)
    @scanner = StringScanner.new(subject)
    @tokens = []
  end

  def tokenize
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
end

class Token

  def self.empty
    @empty ||= new(nil, '')
  end

  attr_reader :type, :matched, :value

  def initialize(type, matched, value = nil)
    @type = type
    @matched = matched
    @value = value || matched
  end

  def to_yaml
    [type, matched, value].uniq.compact.join(' | ')
  end

end
