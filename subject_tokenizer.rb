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
citizenships << [/(граждан\p{Alpha}+)\s+(США|С.Ш.А.)\s*/i, proc {'Гражданин США'}]

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
  Фабрикант
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
  'Гражданский инженер',
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

locations = %w{
  Англия
  Баку
  Бахчисарай
  Берлин
  Варшава
  Венден
  Вена
  Волоковышки
  Гельсингфорс
  Германия
  Екатеринбург
  Екатеринославль
  Занза
  Калима
  Керенск
  Либава
  Лодзи
  Минск
  Митава
  Одесса
  Париж
  Рига
  Рига
  Санкт-петербург
  Саратов
  Симферополь
  Сосновая
  Тарус
  Туккума
  Харьков
  Ченстохова
  Шуи
  Ямбург
}.map { |location|
  key = Lingua.stemmer(location, :language => :ru)
  key = Unicode::downcase(key)
  [key, location]
}.to_h

lemmatize_location = lambda do |location|
  key = Lingua.stemmer(location, :language => :ru)
  key = Unicode::downcase(key)
  locations.fetch(key, location)
end

LOCATIONS = [
  [
    /в (городe|гор.|г.|д. )?(?<name>\p{lu}[\p{alpha}\p{pd}&&[^\w]]+)\s*/,
    proc { |m| lemmatize_location.call(m[:name]) }
  ],
  [
    /(гражданин\p{alpha}|жител\p{alpha}+|приписанн\p{alpha}+ к) (города|гор.|г.|д.) (?<name>\p{lu}\p{ll}+)\s*/i,
    proc { |m| lemmatize_location.call(m[:name]) }
  ],
  [
    /(?<name>\p{lu}\p{ll}+) губернии\s*/i,
    proc { |m| Unicode::capitalize(m[:name].sub(/ой$/, 'ая')) + ' губерния' }
  ],
  [
    /(санкт[ \p{Pd}]*)?петербургск\p{alpha}+\s*/i,
    proc { 'Санкт-Петербург' }
  ],
  [/московск\p{alpha}+\s*/i, proc { 'Москва' }]
]



COMPANY_TYPES = [
  'Анонимное общество',
  'Электрическая компания',
  'Американская компания',
  'Электрическое общество',
  'Национальная компания',
  'Генеральная компания',
  'Генеральное общество',
  'Генеральная электрическая компания',
  'Промышленное общество',
  'Машиностроительный завод',
  'Континентальная спичечная компания',
  'Нью-Йоркская компания',
  'Американская винтовая компания',
  'Универсальная компания',
  'Германское акционерное общество',
  'Соединенная свинцовая и масляная компания',
  'Телефонное товарищество',
  'Французское общество',
  'Всеобщему общество',
  'Всеобщая компания',
  'Французская компания',
  'Континентальная компания',
  'Континентальное общество',
  'Гражданское общество',

  'Торговое общество',
  'Акционерная компания',
  'Телеграфная компания',
  'Швейцарское общество',
  'Отделение акционерного общества',
  'Акционерное металлургическое общество',
  'Фабричная компания',
  'Германское общество',
  'Вифлеемская стальная компания',
  'Вервистекое общество',
  'Американская всеобщей компания',
  'Котельный завод',
  'Соединенное акционерное общество',
  'Русское общество',
  'Новое общество',
  'Механический завод',
  'Правление общества',
  'Соединенная компания',
  'Новое немецкое общество',

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
  'Управление',
].map do |o|
  [stem_and_join.call(o), proc { o }]
end

COMPANY_TYPES << [/фабрик\p{alpha}{,2}(\s+|$)/i, proc { 'Фабрика' }]

COMPANY_TYPE_QUALIFIERS = [
  [/с ограниченной ответственностью\s*/i, :matched.to_proc],
  [/(,)? бывш[\.\p{alpha}]+\s*/i,:matched.to_proc]
]

PROPER_NAMES = [
  [/К°/i, proc { 'К°' }],
  [/(друг\p{alpha}+|др.|прочее)\s*/i, proc { 'другие' }],
  [/
    (\p{Pd}?де[\p{Pd}\s]+(л[еая][\p{Pd}\s])?)?
    ((ван|фон)[\p{Pd}\s]+(дер[\p{Pd}\s])?)?
    ([ДдОоМм][׳′'ˈ])?
    \p{Lu}[\p{alpha}\p{Pd}]+
    (\s\p{Pd}\s\p{Lu}[\p{alpha}\p{Pd}]+)?
    (\s+(Дж.|младш\p{alpha}+))?
    \s*/x, proc { |m| m.matched } ],
]


CONNECTORS = [
  /и\s+/,
  /(,)?\s*с передач\p{alpha}+\s*/i,
  /(,)?\s*передан\p{alpha}+( затем)?([\p{alpha}\s]*? собственность)?\s*/i,
  /(,)?\s*торгующ\p{alpha}+ под\s*/i,
  /(,)?\s*служащ\p{alpha}+ в\s/i,
  /(,)?\s*совладельц\p{alpha}+\s/i,
  /,\s*/
].map do |r|
  [r, proc { |m| m.matched }]
end


TOKENS = ActiveSupport::OrderedHash[
  :company_type, COMPANY_TYPES,
  :company_type_qualifier, COMPANY_TYPE_QUALIFIERS,
  :occupation  , OCCUPATIONS ,
  :position    , POSITIONS   ,
  :citizenship , CITIZENSHIPS,
  :location    , LOCATIONS   ,
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
    [/\p{L}\p{Ll}?[,.]\s*/, proc { |m| Unicode::capitalize(m.matched).strip + ' ' }],
    [/[\p{lu}&&[^И]]($|\s+)/, proc { |m| m.matched.strip + '. ' }]
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
        if scanner.scan(/[\p{Pd}\p{word}]+\s*/)
          tokens << Token.new(:word, scanner.matched)
          throw :next, true
        end
        if scanner.scan(/[\p{punct}\p{symbol}]+\s*/)
          tokens << Token.new(:punct, scanner.matched)
          throw :next, true
        end
        if scanner.scan(/.\s*/)
          tokens << Token.new(:unknown, scanner.matched)
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

  def unknown?
    type.in? [:unknown, :word, :punct]
  end

  def adjective?
    @matched.match(/^\p{word}{3,}(ому|ой)\s*$/i)
  end

  def suspicious?
    unknown? && (type == :punct || matched.match(/год|лет|привелег/))
  end

  def nominative_adjective
    @matched
    .gsub(/ому\s*$/, 'ый ')
    .gsub(/ой\s*$/, 'ая ')
  end


  def to_yaml
    [type, matched, value].uniq.compact.join(' | ')
  end

end
