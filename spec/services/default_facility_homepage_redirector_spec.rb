require "rails_helper"

RSpec.describe DefaultFacilityHomepageRedirector do
  let(:facility) { FactoryGirl.create(:facility) }

  context "#redirect_path" do
    context "with active instruments" do
      let(:facility) { reservation.facility }
      let!(:reservation) { create(:purchased_reservation) }

      it "returns the correct path" do
        path = "/#{I18n.t('facilities_downcase')}/#{facility.url_name}/reservations/timeline"

        expect(DefaultFacilityHomepageRedirector.redirect_path(facility)).to eq path
      end
    end
    context "without active instruments" do
      it "returns the correct path" do
        path = "/#{I18n.t('facilities_downcase')}/#{facility.url_name}/orders"

        expect(DefaultFacilityHomepageRedirector.redirect_path(facility)).to eq path
      end
    end
  end
end