class Category
  attr_reader :number, :title

  def self.nil_category
    @nil_category ||= new("0", 'Без отрасли')
  end

  CATEGORY_REGEX = /^(?<number>[\d.]+?)\.? (?<title>.*)$/
  def self.parse(line)
    line.gsub!(/\s+/, ' ')
    line.gsub!(/^\s*|\s*$/, '')
    line.gsub!(/\.?$/, '')
    m = CATEGORY_REGEX.match(line) or fail "Can't parse category: #{line}"
    new(m[:number], m[:title])
  end

  def initialize(number, title)
    @number = number
    @title = title
  end

  def eql?(other)
    number == other.number
  end

  def hash
    number.hash
  end

  def to_s
    title
  end
end


class ClassifierExample

  attr_reader :lines, :categories

  def initialize(categories)
    @categories = categories
    @lines = []
  end

  NUMBER_REGEX = /^(?<number>[\d.]+?)\.?(\s|$)/
  def category_number
    @category_number ||= @lines.last.strip.try do |line|
      NUMBER_REGEX.match(line).try{ |m| m[:number] }
    end
  end

  def category
    categories[category_number]
  end

  def code
    @code ||= lines[0].strip
  end

  def object
    @object ||= lines[1..-1].join(" ")
  end

  def parse_line(line)
    @lines << line
    self
  end

end


class Classifier

  def nbc
    @nbc ||= StuffClassifier::Bayes.new('titles', :language => 'ru').tap do |nbc|
      nbc.tokenizer.preprocessing_regexps = []
      nbc.tokenizer.ignore_words = []
    end
  end

  def train(examples)
    examples.each do |example|
      next if example.category.nil? || example.object.nil?
      nbc.train(example.category, example.object)
    end
  end

  def classify(title)
    length = nbc.tokenizer.each_word(title.object).length
    title.category_scores = nbc.cat_scores(title.object).map do |cat, score|
      [cat, score * length]
    end
  end

end
