
class Category
  attr_reader :number, :title

  CATEGORY_REGEX = /^(?<number>[\d.]+?)\.? (?<title>.*)$/
  def initialize(line)
    line.gsub!(/\s+/, ' ')
    line.gsub!(/^\s*|\s*$/, '')
    line.gsub!(/\.?$/, '')
    m = CATEGORY_REGEX.match(line) or fail "Can't parse category: #{line}"
    @number = m[:number]
    @title = m[:title]
  end
end


class ClassifierExample

  attr_reader :lines, :categories

  def initialize(categories)
    @categories = categories
    @lines = []
  end

  def category_number
    @category_number ||= @lines.last.strip
  end

  def category
    categories[category_number]
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
      next if example.category.nil?
      nbc.train(example.category.number, example.object)
    end
  end

  def classify(title)
    title.categories = [nbc.classify(title.object)] unless title.object.nil?
  end

end
