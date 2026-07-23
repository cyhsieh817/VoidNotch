import Foundation

/// 對外連結單一真相源——網域再遷移只改這裡（2026-07-21 死網域事故的結構性防再犯）。
public enum VoidNotchLinks {
    public static let site = URL(string: "https://voidnotch.labgrimoire.com")!
    public static let updateEndpoint = URL(string: "https://voidnotch.labgrimoire.com/downloads/version.json")!
}
