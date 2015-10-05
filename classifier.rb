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

  def ==(other)
    other.present? && number == other.number
  end

  def eql?(other)
    other.present? && number == other.number
  end

  def hash
    number.hash
  end

  def parents
    @parents || []
  end

  def set_parents(categories)
    @parents = number.split('.').slice(0...-1)
      .reduce([]) { |nums, num| nums << [nums.last, num].compact.join('.') }
      .map{ |n| categories[n] }
  end

  def with_parents
    parents + [self]
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

  def create_nbc(name)
    StuffClassifier::Bayes.new(name, :language => 'ru').tap do |nbc|
      tokenizer = nbc.tokenizer
      tokenizer.preprocessing_regexps = []
      tokenizer.ignore_words = []
      def tokenizer.each_word(string)
        words = []
        string
          .split(/[^\p{word}]+/)
          .reject(&:blank?)
          .map { |w| Unicode.downcase(@stemmer.stem(w)) }
          .each{ |w| words << (block_given? ? (yield w) : w) }
        return words
      end
    end
  end

  def nbc
    @nbc ||= create_nbc('titles')
  end

  def top_nbc
    @top_nbc ||= create_nbc('titles_top')
  end

  def train(examples)
    examples.each do |example|
      next if example.category.nil? || example.object.nil?
      nbc.train(example.category, example.object)
      top_nbc.train(example.category.with_parents.first, example.object)
    end
  end

  def classify(title)
    # length = top_nbc.tokenizer.each_word(title.object).length
    title.category_scores = nbc.cat_scores(title.object).map do |cat, score|
      [cat, score]
    end
  end

end
