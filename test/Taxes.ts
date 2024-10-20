import { ethers, upgrades } from "hardhat";
import {
  time,
  loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { expect } from "chai";
import {
  Taxes,
  ERC20Mock,
  Gateway,
  Taxes__factory,
  Gateway__factory,
  ERC20Mock__factory,
} from "../typechain-types";

describe("Taxes", function () {
  async function deployFixture() {
    const [owner, admin, user1, user2, user3] = await ethers.getSigners();

    const Gateway = (await ethers.getContractFactory(
      "Gateway"
    )) as Gateway__factory;
    const gateway = (await upgrades.deployProxy(Gateway, [admin.address], {
      initializer: "initializeGateway",
      initialOwner: admin.address,
    })) as unknown as Gateway;
    await gateway.waitForDeployment();
    const gatewayAddr = await gateway.getAddress();

    const Taxes = (await ethers.getContractFactory("Taxes")) as Taxes__factory;
    const taxes = (await upgrades.deployProxy(
      Taxes,
      [admin.address, gatewayAddr],
      {
        initializer: "initializeTaxes",
        initialOwner: admin.address,
      }
    )) as unknown as Taxes;
    await taxes.waitForDeployment();
    const taxesAddr = await taxes.getAddress();

    const ERC20Mock = (await ethers.getContractFactory(
      "ERC20Mock"
    )) as ERC20Mock__factory;
    const erc20Mock = (await upgrades.deployProxy(
      ERC20Mock,
      ["Mock Token", "MTK", admin.address],
      {
        initializer: "initializeERC20Mock",
        initialOwner: admin.address,
      }
    )) as unknown as ERC20Mock;
    await erc20Mock.waitForDeployment();
    const erc20MockAddr = await erc20Mock.getAddress();

    await gateway.connect(owner).batchEnlistTokens([erc20MockAddr]);

    return {
      taxes,
      taxesAddr,
      gateway,
      gatewayAddr,
      erc20Mock,
      erc20MockAddr,
      owner,
      admin,
      user1,
      user2,
      user3,
    };
  }

  describe("Initialization", function () {
    it("Should set the right admin", async function () {
      const { taxes, admin } = await loadFixture(deployFixture);
      expect(await taxes.owner()).to.equal(admin.address);
    });

    // it("Should set the right gateway", async function () {
    //   const { taxes, gateway, gatewayAddr } = await loadFixture(deployFixture);
    //   // Assuming there's a getter for the gateway address
    //   expect(await taxes.gateway()).to.equal(gateway.address);
    // });
  });

  describe("Cooperative Creation", function () {
    it("Should create a cooperative with correct parameters", async function () {
      const { taxes, user1, user2, erc20Mock, erc20MockAddr } =
        await loadFixture(deployFixture);
      const name = "Test Cooperative";
      const description = "A test cooperative";
      const logo = "test_logo.png";
      const contributionAmount = ethers.parseEther("1");
      const contributionPeriod = 30 * 24 * 60 * 60; // 30 days
      const initialMembers = [user1.address, user2.address];
      const payoutScheme = 0; // ROTATING

      await expect(
        taxes
          .connect(user1)
          .createCooperative(
            name,
            description,
            logo,
            contributionAmount,
            contributionPeriod,
            initialMembers,
            erc20MockAddr,
            payoutScheme
          )
      ).to.emit(taxes, "CooperativeCreated");

      const cooperativeInfo = await taxes.getCooperativeInfo(0);
      expect(cooperativeInfo.name).to.equal(name);
      expect(cooperativeInfo.description).to.equal(description);
      expect(cooperativeInfo.logo).to.equal(logo);
      expect(cooperativeInfo.creator).to.equal(user1.address);
      expect(cooperativeInfo.contributionAmount).to.equal(contributionAmount);
      expect(cooperativeInfo.contributionPeriod).to.equal(contributionPeriod);
      expect(cooperativeInfo.payoutScheme).to.equal(payoutScheme);
    });

    it("Should revert if contribution amount is zero", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await expect(
        taxes
          .connect(user1)
          .createCooperative(
            "Test",
            "Test",
            "test.png",
            0,
            30 * 24 * 60 * 60,
            [user1.address, user2.address],
            erc20MockAddr,
            0
          )
      ).to.be.revertedWith("Dexa: 4");
    });

    it("Should revert if contribution period is zero", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await expect(
        taxes
          .connect(user1)
          .createCooperative(
            "Test",
            "Test",
            "test.png",
            ethers.parseEther("1"),
            0,
            [user1.address, user2.address],
            erc20MockAddr,
            0
          )
      ).to.be.revertedWith("Dexa: 7");
    });
  });

  describe("Joining Cooperative", function () {
    it("Should allow a new member to join", async function () {
      const { taxes, user1, user2, user3, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await expect(taxes.connect(user3).joinCooperative(0))
        .to.emit(taxes, "MemberJoined")
        .withArgs(0, user3.address);

      const memberInfo = await taxes.getMemberInfo(0, user3.address);
      expect(memberInfo.isMember).to.be.true;
    });

    it("Should revert if member tries to join twice", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await expect(taxes.connect(user1).joinCooperative(0)).to.be.revertedWith(
        "Dexa: 2"
      );
    });
  });

  describe("Contributing", function () {
    it("Should allow member to contribute", async function () {
      const {
        taxes,
        taxesAddr,
        user1,
        admin,
        user2,
        erc20MockAddr,
        erc20Mock,
      } = await loadFixture(deployFixture);
      const contributionAmount = ethers.parseEther("1");
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          contributionAmount,
          1,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await erc20Mock
        .connect(admin)
        .mint(user1.address, ethers.parseEther("2"));
      await erc20Mock.connect(user1).approve(taxesAddr, contributionAmount);
      const allowance = await erc20Mock.allowance(user1.address, taxesAddr);
      const balance = await erc20Mock.balanceOf(user1.address);

      console.log(user1.address);
      console.log(allowance);
      console.log(balance);

      await expect(taxes.connect(user1).contribute(0))
        .to.emit(taxes, "ContributionMade")
        .withArgs(0, user1.address, contributionAmount);

      const memberInfo = await taxes.getMemberInfo(0, user1.address);
      expect(memberInfo.totalContributed).to.equal(contributionAmount);
    });

    it("Should revert if non-member tries to contribute", async function () {
      const { taxes, user1, user2, user3, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await expect(taxes.connect(user3).contribute(0)).to.be.revertedWith(
        "Not a member of this cooperative"
      );
    });

    it("Should revert if contribution is made before the next contribution date", async function () {
      const {
        taxes,
        admin,
        taxesAddr,
        user1,
        user2,
        erc20MockAddr,
        erc20Mock,
      } = await loadFixture(deployFixture);
      const contributionAmount = ethers.parseEther("1");
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          contributionAmount,
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await erc20Mock.connect(admin).mint(user1.address, contributionAmount);
      await erc20Mock.connect(user1).approve(taxesAddr, contributionAmount);

      await expect(taxes.connect(user1).contribute(0)).to.be.revertedWith(
        "Dexa: 7"
      );
    });
  });

  describe("Payout", function () {
    it("Should process payout when all members have contributed", async function () {
      const {
        taxes,
        taxesAddr,
        admin,
        user1,
        user2,
        erc20MockAddr,
        erc20Mock,
      } = await loadFixture(deployFixture);
      const contributionAmount = ethers.parseEther("1");
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          contributionAmount,
          1,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await erc20Mock.connect(admin).mint(user1.address, contributionAmount);
      await erc20Mock.connect(admin).mint(user2.address, contributionAmount);
      await erc20Mock.connect(user1).approve(taxesAddr, contributionAmount);
      await erc20Mock.connect(user2).approve(taxesAddr, contributionAmount);

      await taxes.connect(user1).contribute(0);
      await expect(taxes.connect(user2).contribute(0)).to.emit(
        taxes,
        "PayoutMade"
      );

      const cooperativeInfo = await taxes.getCooperativeInfo(0);
      expect(cooperativeInfo.totalContributions).to.equal(0);
      expect(cooperativeInfo.currentRound).to.equal(1);
    });
  });

  describe("Proposal Creation and Voting", function () {
    it("Should allow member to create a proposal", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await expect(taxes.connect(user1).createProposal(0, "Test Proposal"))
        .to.emit(taxes, "ProposalCreated")
        .withArgs(0, 0, "Test Proposal");
    });

    it("Should allow members to vote on a proposal", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await taxes.connect(user1).createProposal(0, "Test Proposal");

      await expect(taxes.connect(user1).vote(0, 0, true))
        .to.emit(taxes, "Voted")
        .withArgs(0, user1.address, true);

      await expect(taxes.connect(user2).vote(0, 0, false))
        .to.emit(taxes, "Voted")
        .withArgs(0, user2.address, false);
    });

    it("Should revert if member tries to vote twice", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await taxes.connect(user1).createProposal(0, "Test Proposal");
      await taxes.connect(user1).vote(0, 0, true);

      await expect(taxes.connect(user1).vote(0, 0, false)).to.be.revertedWith(
        "Already voted"
      );
    });

    it("Should allow proposal execution after voting period", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await taxes.connect(user1).createProposal(0, "Test Proposal");
      await taxes.connect(user1).vote(0, 0, true);
      await taxes.connect(user2).vote(0, 0, false);

      await time.increase(3 * 24 * 60 * 60 + 1); // 3 days + 1 second

      await expect(taxes.connect(user1).executeProposal(0, 0))
        .to.emit(taxes, "ProposalExecuted")
        .withArgs(0);
    });
  });

  describe("Member Prosecution", function () {
    it("Should allow member prosecution", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await expect(taxes.connect(user1).prosecuteMember(0, user2.address))
        .to.emit(taxes, "MemberProsecuted")
        .withArgs(0, user2.address, 1);

      const memberInfo = await taxes.getMemberInfo(0, user2.address);
      expect(memberInfo.strikes).to.equal(1);
    });

    it("Should ban member after MAX_STRIKES", async function () {
      const { taxes, user1, user2, erc20MockAddr } = await loadFixture(
        deployFixture
      );
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          ethers.parseEther("1"),
          30 * 24 * 60 * 60,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      for (let i = 0; i < 2; i++) {
        await taxes.connect(user1).prosecuteMember(0, user2.address);
      }

      await expect(taxes.connect(user1).prosecuteMember(0, user2.address))
        .to.emit(taxes, "MemberBanned")
        .withArgs(0, user2.address);

      const memberInfo = await taxes.getMemberInfo(0, user2.address);
      expect(memberInfo.isMember).to.be.false;
    });
  });

  describe("Fee Management", function () {
    it("Should allow owner to set fee percentage", async function () {
      const { taxes, admin } = await loadFixture(deployFixture);
      const newFeePercentage = 200; // 2%

      await expect(taxes.connect(admin).setFeePercentage(newFeePercentage))
        .to.emit(taxes, "FeePercentageUpdated")
        .withArgs(newFeePercentage);

      expect(await taxes.feePercentage()).to.equal(newFeePercentage);
    });

    it("Should revert if non-owner tries to set fee percentage", async function () {
      const { taxes, user1 } = await loadFixture(deployFixture);
      await expect(
        taxes.connect(user1).setFeePercentage(200)
      ).to.be.revertedWithCustomError;
    });

    it("Should allow owner to withdraw fees", async function () {
      const {
        taxes,
        taxesAddr,
        admin,
        user1,
        user2,
        erc20MockAddr,
        erc20Mock,
      } = await loadFixture(deployFixture);
      const contributionAmount = ethers.parseEther("1");
      await taxes
        .connect(user1)
        .createCooperative(
          "Test",
          "Test",
          "test.png",
          contributionAmount,
          1,
          [user1.address, user2.address],
          erc20MockAddr,
          0
        );

      await erc20Mock.connect(admin).mint(user1.address, contributionAmount);
      await erc20Mock.connect(user1).approve(taxesAddr, contributionAmount);
      await taxes.connect(user1).contribute(0);

      const feeAmount = (contributionAmount * BigInt(100)) / BigInt(10000); // 1% fee

      await expect(taxes.connect(admin).withdrawFees(erc20MockAddr))
        .to.emit(taxes, "FeesWithdrawn")
        .withArgs(erc20MockAddr, feeAmount);

      expect(await erc20Mock.balanceOf(admin.address)).to.equal(feeAmount);
    });
  });
});
