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
    /(времен\p{alpha}+\s+)?((?<guild>\d[\p{Pd}oй ]*|первой|второй) гильдии )?купц\p{alpha}\s*/i,
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
      '((гвардии|артиллерии) )?(инженер[\\p{Pd}\\sу]*)?' +
      stem_and_join.call(s).source,
    Regexp::IGNORECASE)
  [r, proc { s }]
end

LOCATIONS = [
  [
    /жител\p{alpha}+ (города|гор.|г.|д.) (?<name>\p{lu}\p{ll}+)\s*/i,
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
  'Товарищество',
  'Торговый дом',
  'Акционерное общество',
  'Общество',
  'Компания',
].map do |o|
  [stem_and_join.call(o), proc { o }]
end

CONNECTORS = [
  /и\s*/,
  /(,)?\s*c передач\p{alpha}+\s*/,
  /(,)?\s*передан\p{alpha}+\s*/,
  /(,)?\s*торгующ\p{alpha}+ под\s*/,
  /,\s*/
].map do |r|
  [r, proc { |m| m.matched }]
end
