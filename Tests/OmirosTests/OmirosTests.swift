//
//  OmirosTests
//
//  Copyright (C) 2021 Dmytro Lisitsyn
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import XCTest
import os
@testable import Omiros

class OmirosTests: XCTestCase {

    var omiros: Omiros!

    override func setUp() {
        omiros = Omiros("OmirosTests", inMemory: true)
    }

    override func tearDown() async throws {
        try await omiros.deleteFile()
    }

    func testFetchingAndSaving() async throws {
        var fetched = try await omiros.fetchFirst(Person.self)
        XCTAssert(fetched == nil)

        let entity = Person()

        try await omiros.save(entity)

        fetched = try await omiros.fetchFirst(Person.self)

        XCTAssertEqual(entity.firstName, fetched?.firstName)
        XCTAssertEqual(entity.lastName, fetched?.lastName)
        XCTAssertEqual(entity.dateOfBirth, fetched?.dateOfBirth)
        XCTAssertEqual(entity.height, fetched?.height)
        XCTAssertEqual(entity.additionalData, fetched?.additionalData)
        XCTAssertEqual(entity.homePageURL, fetched?.homePageURL)
    }

    func testFiltering() async throws {
        var entities: [Person] = []
        for index in 0..<10000 {
            entities.append(.init(firstName: "\(index)", lastName: "\(index)"))
        }
        for _ in 0..<100 {
            entities.append(Person(firstName: "Jack", lastName: "White"))
            entities.append(Person(firstName: "Jack", lastName: "Black"))
            entities.append(Person(firstName: "Jack", lastName: "Gray"))
            entities.append(Person(firstName: "Lucy", lastName: "White"))
        }
        entities.append(Person(firstName: "Andrea", lastName: "Smith"))
        entities.shuffle()

        try await omiros.save(entities)

        let query = OmirosQuery<Person>(where: .all([
            .equal(.firstName, "Jack"),
            .any([
                .equal(.lastName, "White"),
                .equal(.lastName, "Black")
            ])
        ]))

        let fetched = try? await omiros.fetch(Person.self, with: query)
        XCTAssertEqual(fetched?.count, 200)
    }

    func testCounting() async throws {
        var owner = Owner()

        var ebony = Dog(ownerID: owner.id, name: "Ebony")
        ebony.collarCaption = "Ebony"
        ebony.collarCaption = nil

        var ivory = Dog(ownerID: owner.id, name: "Ivory")
        ivory.collarCaption = "Evory"
        ivory.collarCaption = "Love Ivory"

        owner.dogs = [ebony, ivory]

        try await omiros.save(owner)

        let ownerCount = try await omiros.count(Owner.self)
        let dogCount = try await omiros.count(Dog.self)
        let filteredDogCount = try await omiros.count(Dog.self, with: .init(where: .like(.collarCaption, "%love%")))

        XCTAssertEqual(ownerCount, 1)
        XCTAssertEqual(dogCount, 2)
        XCTAssertEqual(filteredDogCount, 1)
    }

    func testOrderingAndPagination() async throws {
        var entities: [Person] = []

        for _ in 0..<100 {
            entities.append(Person(firstName: "Jack", lastName: "White"))
        }
        for _ in 0..<100 {
            entities.append(Person(firstName: "Jack", lastName: "Black"))
        }
        for _ in 0..<100 {
            entities.append(Person(firstName: "Peter", lastName: "Parker"))
        }
        for _ in 0..<100 {
            entities.append(Person(firstName: "Brandon", lastName: "Smith"))
        }

        try await omiros.save(entities)

        var query = OmirosQuery<Person>()
        query.order = [.asc(.firstName), .asc(.lastName)]
        query.offset = 200
        query.limit = 100

        let fetched = try? await omiros.fetch(Person.self, with: query)
        XCTAssertEqual(fetched?.count, 100)

        XCTAssertEqual(fetched?.first?.firstName, "Jack")
        XCTAssertEqual(fetched?.first?.lastName, "White")

        XCTAssertEqual(fetched?.last?.firstName, "Jack")
        XCTAssertEqual(fetched?.last?.lastName, "White")
    }

    func testNotInQueryParameters() async throws {
        var entities: [Person] = []

        for _ in 0..<10 {
            entities.append(Person(firstName: "Jack", lastName: "White"))
        }
        for _ in 0..<10 {
            entities.append(Person(firstName: "Jack", lastName: "Black"))
        }
        for _ in 0..<10 {
            entities.append(Person(firstName: "Peter", lastName: "Parker", height: 190))
        }
        for _ in 0..<10 {
            entities.append(Person(firstName: "Rihanna"))
        }
        entities.append(Person(firstName: "Bree", lastName: "Whale", height: 180))

        try await omiros.save(entities)

        var query = OmirosQuery<Person>(where: .all([
            .not(.equal(.firstName, "Jack")),
            .not(.equal(.firstName, "Rihanna"))
        ]))
        var fetched = try? await omiros.fetch(with: query)

        XCTAssertEqual(fetched?.count, 11)

        query = OmirosQuery(where:
            .not(.all([
                .equal(.firstName, "Jack"),
                .equal(.lastName, "Black")
            ]))
        )
        fetched = try? await omiros.fetch(with: query)

        XCTAssertEqual(fetched?.count, 31)

        query = OmirosQuery(where: .not(.equal(.lastName, nil)))
        fetched = try? await omiros.fetch(with: query)

        XCTAssertEqual(fetched?.count, 31)

        query = OmirosQuery(where: .not(.greaterThanOrEqual(.height, 180)))
        fetched = try? await omiros.fetch(with: query)

        XCTAssertEqual(fetched?.count, 30)

        query = OmirosQuery(where: .not(.like(.lastName, "Wh%")))
        fetched = try? await omiros.fetch(with: query)

        XCTAssertEqual(fetched?.count, 20)
    }

    func testSavingAndFetchingWithRelations() async throws {
        var entity = Owner()
        entity.dogs.append(Dog(ownerID: entity.id, name: "Ebony"))
        entity.dogs.append(Dog(ownerID: entity.id, name: "Ivory"))

        try await omiros.save(entity)

        let fetched: Owner? = try await omiros.fetchFirst()

        XCTAssertEqual(entity.id, fetched?.id)
        XCTAssertEqual(entity.dogs.count, fetched?.dogs.count)
        XCTAssertEqual(entity.dogs.first?.ownerID, fetched?.dogs.first?.ownerID)
        XCTAssertEqual(entity.dogs.first?.name, fetched?.dogs.first?.name)
        XCTAssertEqual(entity.dogs.last?.ownerID, fetched?.dogs.last?.ownerID)
        XCTAssertEqual(entity.dogs.last?.name, fetched?.dogs.last?.name)
    }

    func testSavingAndDeletingWithRelations() async throws {
        var entity = Owner()
        entity.dogs.append(Dog(ownerID: entity.id, name: "Ebony"))
        entity.dogs.append(Dog(ownerID: entity.id, name: "Ivory"))

        try await omiros.save(entity)

        var fetchedDogs: [Dog] = try await omiros.fetch()
        XCTAssertEqual(fetchedDogs.count, entity.dogs.count)

        try await omiros.delete(Owner.self)

        let fetchedOwner: Owner? = try await omiros.fetchFirst()
        XCTAssertNil(fetchedOwner)

        fetchedDogs = try await omiros.fetch()
        XCTAssertTrue(fetchedDogs.isEmpty)
    }

    func testSavingExisting() async throws {
        var owner = Owner()

        var ebony = Dog(ownerID: owner.id, name: "Ebony")
        ebony.collarCaption = "Ebony"

        var ivory = Dog(ownerID: owner.id, name: "Ivory")
        ivory.collarCaption = "Evory"

        let pinky = Dog(ownerID: owner.id, name: "Pinky")

        owner.dogs = [ebony, ivory, pinky]

        try await omiros.save(owner)

        ebony.collarCaption = "Love Ebony"
        ivory.collarCaption = "Love Ivory"
        owner.dogs = [ebony, ivory]

        try await omiros.save(owner)

        let owners = try await omiros.fetch(Owner.self)
        let dogs = try await omiros.fetch(Dog.self, with: .init(order: [.asc(.collarCaption)]))

        XCTAssertEqual(owners.count, 1)
        XCTAssertEqual(dogs.count, 2)
        XCTAssertEqual(owners.first?.name, owner.name)
        XCTAssertEqual(dogs[0], owner.dogs[0])
        XCTAssertEqual(dogs[1], owner.dogs[1])
    }

    func testParallelOperations() async throws {
        async let saving: Void = withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let entities = stride(from: 0, to: 100, by: 1).map({ _ in Person.init() })
                    try await self.omiros.save(entities)
                }
            }
            try await group.waitForAll()
        }

        async let fetching: Void = withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    _ = try await self.omiros.fetch(Person.self)
                }
            }
            try await group.waitForAll()
        }

        let _ = try await (saving, fetching)

        let fetched = try await omiros.fetch(Person.self)
        XCTAssertEqual(fetched.count, 2000)
    }

    func testDeleteAll() async throws {
        var entities: [Person] = []
        for _ in 0..<100 {
            entities.append(.init())
        }

        try await omiros.save(entities)

        var fetched = try await omiros.fetch(Person.self)
        XCTAssertEqual(fetched.count, 100)

        try await omiros.deleteFile()

        fetched = try await omiros.fetch(Person.self)
        XCTAssertEqual(fetched.count, 0)
    }

    func testIndexing() async throws {
        var entities: [Person] = []
        entities.append(.init(id: "0", firstName: "Paulino", lastName: "Scheyer"))
        entities.append(.init(id: "1", firstName: "Julieann", lastName: "Waeles"))
        entities.append(.init(id: "2", firstName: "Haitham", lastName: "Petru"))
        entities.append(.init(id: "3", firstName: "Kary", lastName: "Beyreiss"))
        entities.append(.init(id: "4", firstName: "Cvetelina", lastName: "Ibarguren"))
        entities.append(.init(id: "5", firstName: "Joy", lastName: "Agibaloff"))
        entities.append(.init(id: "6", firstName: "Jianfang", lastName: "Walls"))
        entities.append(.init(id: "7", firstName: "Cristinela", lastName: "Murchadh"))
        entities.append(.init(id: "8", firstName: "Bekkaye", lastName: "Shields"))
        entities.append(.init(id: "9", firstName: "Kristy", lastName: "Shields"))
        entities.append(.init(id: "10", firstName: "Kristy", lastName: "Handric"))
        try await omiros.save(entities)

        let fetched = try await omiros.fetch(with: OmirosQuery<Person>(order: [.asc(.lastName)]))

        XCTAssertEqual(fetched.first?.firstName, "Joy")
        XCTAssertEqual(fetched.first?.lastName, "Agibaloff")

        XCTAssertEqual(fetched.last?.firstName, "Jianfang")
        XCTAssertEqual(fetched.last?.lastName, "Walls")
    }

}
