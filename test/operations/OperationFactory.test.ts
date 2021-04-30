import chai, { expect } from "chai";
import { ethers } from "hardhat";
import { solidity } from "ethereum-waffle";
import {
  Contract,
  ContractFactory,
  BigNumber,
  utils,
  BigNumberish,
} from "ethers";
import { Provider } from "@ethersproject/providers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import {
  advanceTimeAndBlock,
  encodeParameters,
  filterStructFields,
  latestBlocktime,
} from "../shared/utilities";

chai.use(solidity);

describe("OperationFactory", () => {
  const { provider } = ethers;

  let owner: SignerWithAddress;
  let controller: SignerWithAddress;

  before("setup", async () => {
    [owner, controller] = await ethers.getSigners();
  });

  const hash1 =
    "0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef";
  const hash2 =
    "0xbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdead";

  it("works well", async () => {
    const Operation = await ethers.getContractFactory("Operation");
    const operation = await Operation.connect(owner).deploy();
    await operation
      .connect(owner)
      .initialize(
        encodeParameters(
          ["address", "bytes32", "address", "address"],
          [controller.address, hash1, owner.address, owner.address]
        )
      );

    const Factory = await ethers.getContractFactory("OperationFactory");
    const factory = await Factory.connect(owner).deploy();
    await factory.connect(owner).transferOperator(controller.address);

    await factory.connect(owner).setStandardOperation(0, operation.address);
    expect(await factory.standards(0)).to.eq(operation.address);

    await factory.connect(owner).pushTerraAddresses([hash2]);
    expect(await factory.fetchNextTerraAddress()).to.eq(hash2);

    const tx = await factory.connect(controller).build(0, controller.address);
    const receipt = await provider.getTransactionReceipt(tx.hash);
    const desc = factory.interface.parseLog(receipt.logs[0]);

    expect(desc.args.deployer).to.eq(controller.address);
    expect(desc.args.terraAddress).to.eq(hash2);

    const instance = await ethers.getContractAt(
      "Operation",
      desc.args.instance
    );
    expect(await operation.terraAddress()).to.eq(hash1);
    expect(await instance.terraAddress()).to.eq(hash2);

    expect(operation.address).not.to.eq(instance.address);
  });
});
