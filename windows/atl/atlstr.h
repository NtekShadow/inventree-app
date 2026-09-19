#pragma once
#include <windows.h>
#include <string>
#include <vector>

// Lightweight shim for ATL string conversion classes (CA2W, CW2A)
// required by flutter_secure_storage_windows when ATL is not installed in Visual Studio Build Tools.

class CA2W {
public:
    explicit CA2W(const char* str) {
        if (str) {
            int len = MultiByteToWideChar(CP_UTF8, 0, str, -1, NULL, 0);
            if (len > 0) {
                buffer.resize(len);
                MultiByteToWideChar(CP_UTF8, 0, str, -1, buffer.data(), len);
                m_psz = buffer.data();
                return;
            }
        }
        buffer = { 0 };
        m_psz = buffer.data();
    }

    CA2W(const CA2W& other) : buffer(other.buffer) {
        m_psz = buffer.data();
    }

    CA2W& operator=(const CA2W& other) {
        if (this != &other) {
            buffer = other.buffer;
            m_psz = buffer.data();
        }
        return *this;
    }

    operator LPCWSTR() const { return m_psz; }
    wchar_t* m_psz;

private:
    std::vector<wchar_t> buffer;
};

class CW2A {
public:
    explicit CW2A(const wchar_t* wstr) {
        if (wstr) {
            int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, NULL, 0, NULL, NULL);
            if (len > 0) {
                buffer.resize(len);
                WideCharToMultiByte(CP_UTF8, 0, wstr, -1, buffer.data(), len, NULL, NULL);
                m_psz = buffer.data();
                return;
            }
        }
        buffer = { 0 };
        m_psz = buffer.data();
    }

    CW2A(const CW2A& other) : buffer(other.buffer) {
        m_psz = buffer.data();
    }

    CW2A& operator=(const CW2A& other) {
        if (this != &other) {
            buffer = other.buffer;
            m_psz = buffer.data();
        }
        return *this;
    }

    operator LPCSTR() const { return m_psz; }
    operator std::string() const { return m_psz ? std::string(m_psz) : std::string(); }
    char* m_psz;

private:
    std::vector<char> buffer;
};
