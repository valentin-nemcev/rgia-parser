
class ManualPerson
  attr_reader :full_name

  def person?
    true
  end

  def initialize(full_name)
    @full_name = full_name
  end

  def author_name
    ''
  end

  def author_patronymic
    ''
  end

  def author
    full_name.split(' ', 2).first
  end

  def author_initials
    full_name.split(' ', 2).second
  end

end


class ManualCompany
  attr_reader :full_name

  def person?
    false
  end

  def initialize(full_name)
    @full_name = full_name
  end

  def author_name
    ''
  end

  def author_patronymic
    ''
  end

  def author
    full_name
  end

  def author_initials
    ''
  end

end



class ManualTitle

  def self.from_hash(hash, categories)
    t = self.new(categories)
    hash.each do |key, value|
      t.send("#{key}=", value.try(:strip))
    end
    t
  end

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
    :title        , 'Заголовок'            ,
    # :warnings_s   , 'Проблемы'             ,
  ]

  FIELDS.keys.each do |key|
    attr_accessor key
  end

  def is_manual
    true
  end

  def is_manual_s
    'Да'
  end


  CITIZENSHIPS = Hash[
    '1.2.1' => 'Великобританский подданный',
    '1.2.2' => 'Французский подданный',
    '1.2.3' => 'Германский подданный',
    '1.2.4' => 'Австро-венгерский подданный',
    '1.2.5' => 'Швейцарский подданный',
    '1.2.6' => 'Итальянский подданный',
    '1.2.7' => 'Испанский подданный',
    '1.2.8' => 'Подданный США',
    '1.1'   => 'Российский подданный',
    '1.2'   => 'Иностранец',
  ]

  attr_reader :citizenship
  def citizenship_s=(str)
    if str.present?
      CITIZENSHIPS.each do |key, value|
        str = str.gsub(key, value)
      end
    end
    @citizenship = (str || '').split(',').map(&:strip).uniq
  end

  def citizenship_s
    @citizenship.join(', ')
  end

  attr_reader :position
  def position_s=(str)
    @position = (str || '').split(',').map(&:strip).uniq
  end

  def position_s
    @position.join(', ')
  end

  attr_reader :occupation
  def occupation_s=(str)
    @occupation = (str || '').split(',').map(&:strip).uniq
  end

  def occupation_s
    @occupation.join(', ')
  end

  attr_reader :location
  def location_s=(str)
    @location = (str || '').split(',').map(&:strip).uniq
  end

  def location_s
    @location.join(', ')
  end


  attr_reader :authors, :classifier_categories
  def initialize(categories)
    @authors = []
    @classifier_categories = categories
  end

  def classifier_categories_inverse
    @classifier_categories_inverse ||=
      begin
        Hash[classifier_categories.map do |num, cat|
          [cat.title, cat]
        end]
      end
  end


  def needs_classification?
    false
  end

  attr_reader :category
  def category_s=(cat_str)
    cat_str = cat_str.try(:strip)
    cat = classifier_categories[cat_str] || classifier_categories_inverse[cat_str]
    fail "Unknown manual category #{cat_str}" if cat_str.present? && cat.nil?
    @category = cat
  end

  def category_s
    @category.to_s
  end


  (1..5).each do |i|
    define_method("author#{i}=") do |author|
      authors.push ManualPerson.new(author) if author.present?
    end
  end

  def company_name=(author)
      authors.push ManualCompany.new(author) if author.present?
  end

  prepend Authors

  include FinalFields

  def to_row
    Title::FIELDS.keys.map do |field|
      send field
    end
  end

  def warnings
    @warnings ||= []
  end

  def warn(msg)
    warnings << msg
    self
  end

  def warnings_s
    warnings.join(', ')
  end

  def validate
  end

  def valid?
    warnings.empty?
  end


end
