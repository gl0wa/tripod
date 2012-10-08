require "spec_helper"

describe Tripod::Persistence do

  let(:unsaved_person) do
    @unsaved_uri = @uri = 'http://uri'
    @graph1 = RDF::Graph.new
    stmt = RDF::Statement.new
    stmt.subject = RDF::URI.new(@uri)
    stmt.predicate = RDF::URI.new('http://pred')
    stmt.object = RDF::URI.new('http://obj')
    @graph1 << stmt
    p = Person.new(@uri, 'http://graph')
    p.hydrate!(@graph1)
    p
  end

  let(:saved_person) do
    @saved_uri = @uri2 = 'http://uri2'
    @graph2 = RDF::Graph.new
    stmt = RDF::Statement.new
    stmt.subject = RDF::URI.new(@uri2)
    stmt.predicate = RDF::URI.new('http://pred2')
    stmt.object = RDF::URI.new('http://obj2')
    @graph2 << stmt
    p = Person.new(@uri2, 'http://graph')
    p.hydrate!(@graph2)
    p.save
    p
  end


  describe "#save" do

    context 'graph not set' do
      it 'should not succeed' do
        unsaved_person.graph_uri = nil
        unsaved_person.save.should be_false
        unsaved_person.should_not be_valid
        unsaved_person.errors.should_not be_empty
        unsaved_person.errors[:graph_uri].length.should ==1
        unsaved_person.errors[:graph_uri].should == ["can't be blank"]
      end
    end

    context 'uri not set' do
      it 'should not succeed' do
        unsaved_person.uri = nil
        unsaved_person.save.should be_false
        unsaved_person.should_not be_valid
        unsaved_person.errors.should_not be_empty
        unsaved_person.errors[:uri].length.should ==1
        unsaved_person.errors[:uri].should == ["can't be blank"]
      end
    end

    context 'graph and uri set' do

      it 'saves the contents to the db' do
        unsaved_person.save.should be_true

        # try reading the data back out.
        p2 = Person.new(@uri)
        p2.hydrate!
        repo_statements = p2.repository.statements
        repo_statements.count.should == 1
        repo_statements.first.subject.should == RDF::URI.new(@uri)
        repo_statements.first.predicate.should == RDF::URI.new('http://pred')
        repo_statements.first.object.should == RDF::URI.new('http://obj')
      end

      it 'should leave other people untouched' do
        # save the unsaved person
        unsaved_person.save.should be_true

        # read the saved person back out the db, and check he's untouched.
        p2 = Person.new(saved_person.uri)
        p2.hydrate!
        p2.repository.dump(:ntriples).should == saved_person.repository.dump(:ntriples)
      end

    end
  end

  describe "#destroy" do

    it 'removes all triples from the db' do
      saved_person.destroy.should be_true

      # re-load it back into memory
      p2 = Person.new(@saved_uri)
      p2.hydrate!
      p2.repository.should be_empty # nothing there any more!
    end

  end

  describe "#save!" do
    it 'throws an exception if save fails' do
      unsaved_person.uri = nil
      lambda {unsaved_person.save!}.should raise_error(Tripod::Errors::Validations)
    end
  end

  describe "transactions" do

    it "only save on commit" do

      transaction = Tripod::Persistence::Transaction.new

      unsaved_person.save(transaction: transaction)
      saved_person['http://pred2'] = 'blah'
      saved_person.save(transaction: transaction)

      # nothing should have changed yet.
      lambda {Person.find(unsaved_person.uri)}.should raise_error(Tripod::Errors::ResourceNotFound)
      Person.find(saved_person.uri)['http://pred2'].first.to_s.should == RDF::URI.new('http://obj2').to_s

      transaction.commit

      # things should have changed now.
      lambda {Person.find(unsaved_person.uri)}.should_not raise_error()
      Person.find(saved_person.uri)['http://pred2'].first.should == 'blah'

    end

    it "silently ignore invalid saves" do
      transaction = Tripod::Persistence::Transaction.new

      unsaved_person.uri = nil
      unsaved_person.save(transaction: transaction).should be_false

      saved_person['http://pred2'] = 'blah'
      saved_person.save(transaction: transaction).should be_true

      transaction.commit

      # unsaved person still not there
      lambda {Person.find(unsaved_person.uri)}.should raise_error(Tripod::Errors::ResourceNotFound)

      # saved person SHOULD be updated
      Person.find(saved_person.uri)['http://pred2'].first.should == 'blah'
    end

    it "can be aborted" do
      transaction = Tripod::Persistence::Transaction.new

      unsaved_person.save(transaction: transaction)

      transaction.abort()

      transaction.query.should be_blank
    end


  end

end